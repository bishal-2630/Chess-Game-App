from rest_framework import status, permissions
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.decorators import api_view, permission_classes
from django.contrib.auth import get_user_model
from django.utils import timezone
from datetime import timedelta
from .models import GameInvitation
from .game_serializers import UserSerializer, GameInvitationSerializer, CreateInvitationSerializer
from .mqtt_utils import publish_mqtt_notification
from drf_yasg.utils import swagger_auto_schema

User = get_user_model()

class OnlineUsersView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    
    @swagger_auto_schema(auto_schema=None)
    def get(self, request):
        # Get users who were online in the last 5 minutes
        five_minutes_ago = timezone.now() - timedelta(minutes=5)
        online_users = User.objects.filter(
            is_online=True
        ).exclude(id=request.user.id)
        
        serializer = UserSerializer(online_users, many=True)
        return Response({
            'online_users': serializer.data,
            'count': online_users.count()
        })

class AllUsersView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    
    @swagger_auto_schema(auto_schema=None)
    def get(self, request):
        # Get all users except current user
        users = User.objects.exclude(id=request.user.id).order_by('-is_online', 'username')
        serializer = UserSerializer(users, many=True)
        return Response({
            'users': serializer.data,
            'count': users.count()
        })

class UpdateOnlineStatusView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    
    @swagger_auto_schema(auto_schema=None)
    def post(self, request):
        user = request.user
        is_online = request.data.get('is_online', True)
        room_id = request.data.get('room_id', None)
        
        user.is_online = is_online
        if room_id:
            user.current_room = room_id
        elif not is_online:
            user.current_room = None
        
        user.save()
        
        return Response({
            'status': 'updated',
            'is_online': user.is_online,
            'current_room': user.current_room
        })

class SendInvitationView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    
    @swagger_auto_schema(auto_schema=None)
    def post(self, request):
        serializer = CreateInvitationSerializer(
            data=request.data,
            context={'request': request}
        )
        
        if serializer.is_valid():
            invitation = serializer.save()
            
            # Send MQTT notification for background/offline support
            publish_mqtt_notification(
                invitation.receiver.username,
                'game_invitation',
                GameInvitationSerializer(invitation).data
            )
            
            return Response({
                'success': True,
                'invitation': GameInvitationSerializer(invitation).data,
                'message': f'Invitation sent to {invitation.receiver.username}'
            })
        
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

class MyInvitationsView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    
    @swagger_auto_schema(auto_schema=None)
    def get(self, request):
        # Get received invitations that are pending
        invitations = GameInvitation.objects.filter(
            receiver=request.user,
            status='pending'
        ).order_by('-created_at')
        
        serializer = GameInvitationSerializer(invitations, many=True)
        return Response({
            'invitations': serializer.data,
            'count': invitations.count()
        })

class RespondToInvitationView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    
    @swagger_auto_schema(auto_schema=None)
    def post(self, request, invitation_id):
        try:
            invitation = GameInvitation.objects.get(
                id=invitation_id,
                receiver=request.user,
                status='pending'
            )
        except GameInvitation.DoesNotExist:
            return Response({
                'error': 'Invitation not found'
            }, status=status.HTTP_404_NOT_FOUND)
        
        action = request.data.get('action')  # 'accept' or 'decline'
        
        if action == 'accept':
            invitation.status = 'accepted'
            message = f'Invitation from {invitation.sender.username} accepted'
        elif action == 'decline':
            invitation.status = 'declined'
            message = f'Invitation from {invitation.sender.username} declined'
        else:
            return Response({
                'error': 'Invalid action. Use "accept" or "decline"'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        invitation.save()
        
        publish_mqtt_notification(invitation.sender.username, 'invitation_response', {'invitation': GameInvitationSerializer(invitation).data, 'action': action})
        
        return Response({
            'success': True,
            'message': message,
            'invitation': GameInvitationSerializer(invitation).data
        })

@swagger_auto_schema(methods=['POST'], auto_schema=None)
@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
def cancel_invitation(request, invitation_id):
    try:
        invitation = GameInvitation.objects.get(
            id=invitation_id,
            sender=request.user,
            status='pending'
        )
    except GameInvitation.DoesNotExist:
        return Response({
            'error': 'Invitation not found'
        }, status=status.HTTP_404_NOT_FOUND)
    
    invitation.status = 'cancelled'
    invitation.save()
    
    publish_mqtt_notification(
        invitation.receiver.username,
        'invitation_cancelled',
        GameInvitationSerializer(invitation).data
    )
    
    return Response({
        'success': True,
        'message': 'Invitation cancelled'
    })

class SendCallSignalView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    
    @swagger_auto_schema(auto_schema=None)
    def post(self, request):
        receiver_username = request.data.get('receiver_username')
        room_id = request.data.get('room_id')
        
        try:
            receiver = User.objects.get(username=receiver_username)
        except User.DoesNotExist:
             return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)
             
        # Send MQTT notification for background/offline support
        publish_mqtt_notification(
            receiver.username,
            'call_invitation',
            {
                'caller': request.user.username,
                'room_id': room_id,
                'caller_picture': request.user.profile_picture
            }
        )
        
        return Response({'success': True})

class DeclineCallView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    
    @swagger_auto_schema(auto_schema=None)
    def post(self, request):
        caller_username = request.data.get('caller_username')
        room_id = request.data.get('room_id')
        
        try:
            caller = User.objects.get(username=caller_username)
        except User.DoesNotExist:
             return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)
             
        # Send MQTT notification to caller that call was declined
        publish_mqtt_notification(
            caller.username,
            'call_declined',
            {
                'decliner': request.user.username,
                'room_id': room_id
            }
        )
        
        return Response({'success': True})


class CancelCallView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    
    @swagger_auto_schema(auto_schema=None)
    def post(self, request):
        receiver_username = request.data.get('receiver_username')
        room_id = request.data.get('room_id')
        
        try:
            receiver = User.objects.get(username=receiver_username)
        except User.DoesNotExist:
             return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)
             
        # Send MQTT notification that call was cancelled by the caller
        publish_mqtt_notification(
            receiver.username,
            'call_cancelled',
            {
                'caller': request.user.username,
                'room_id': room_id
            }
        )
        
        return Response({'success': True})
