from rest_framework import serializers
from .models import User, GameInvitation

class UserSerializer(serializers.ModelSerializer):
    is_online = serializers.BooleanField(read_only=True)
    last_seen = serializers.DateTimeField(read_only=True)
    current_room = serializers.CharField(read_only=True)
    
    class Meta:
        model = User
        fields = ['id', 'username', 'email', 'first_name', 'last_name', 
                 'profile_picture', 'is_online', 'last_seen', 'current_room']

class GameInvitationSerializer(serializers.ModelSerializer):
    sender = UserSerializer(read_only=True)
    receiver = UserSerializer(read_only=True)
    
    class Meta:
        model = GameInvitation
        fields = ['id', 'sender', 'receiver', 'room_id', 'status', 
                 'created_at', 'updated_at']

class CreateInvitationSerializer(serializers.ModelSerializer):
    receiver_username = serializers.CharField(write_only=True)
    
    class Meta:
        model = GameInvitation
        fields = ['receiver_username', 'room_id']
    
    def create(self, validated_data):
        receiver_username = validated_data.pop('receiver_username')
        room_id = validated_data['room_id']
        sender = self.context['request'].user
        
        try:
            receiver = User.objects.get(username=receiver_username)
        except User.DoesNotExist:
            raise serializers.ValidationError("Receiver not found")
        
        if sender == receiver:
            raise serializers.ValidationError("Cannot invite yourself")
        
        # Check if invitation already exists
        existing = GameInvitation.objects.filter(
            sender=sender,
            receiver=receiver,
            room_id=room_id,
            status='pending'
        ).first()
        
        if existing:
            raise serializers.ValidationError("Invitation already sent")
        
        return GameInvitation.objects.create(
            sender=sender,
            receiver=receiver,
            room_id=room_id
        )
