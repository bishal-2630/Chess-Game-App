from rest_framework import status, permissions
from drf_yasg.utils import swagger_auto_schema
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.decorators import api_view
from django.contrib.auth import get_user_model
from django.core.mail import send_mail
from django.conf import settings
from django.utils import timezone
from django.http import JsonResponse
from rest_framework.permissions import IsAuthenticated
from rest_framework.parsers import JSONParser, BaseParser
import json
import requests
from typing import Dict  # Added for better IDE support
from .livekit_service import LiveKitService

# LiveKit sends Content-Type: application/webhook+json
# DRF's default JSONParser only accepts application/json, causing 415 errors.
class WebhookJsonParser(BaseParser):
    """Accepts application/webhook+json — used by LiveKit webhooks."""
    media_type = 'application/webhook+json'

    def parse(self, stream, media_type=None, parser_context=None):
        return json.loads(stream.read().decode('utf-8'))

from .models import OTP
from .serializers import (
    EmailSerializer, 
    OTPSerializer, 
    PasswordResetSerializer
)

class ConnectivityCheckView(APIView):
    permission_classes = [permissions.AllowAny]
    
    @swagger_auto_schema(auto_schema=None)
    def get(self, request):
        results = {}
        # Test Google HTTP
        try:
            r = requests.get("https://google.com", timeout=5)
            results['google_http'] = f"Success ({r.status_code})"
        except Exception as e:
            results['google_http'] = f"Failed: {str(e)}"
            
        # Test SMTP Port 587
        import socket
        try:
            s = socket.create_connection(("smtp.gmail.com", 587), timeout=5)
            results['smtp_587'] = "Reachable"
            s.close()
        except Exception as e:
            results['smtp_587'] = f"Unreachable: {str(e)}"

        # Test SMTP Port 465
        try:
            s = socket.create_connection(("smtp.gmail.com", 465), timeout=5)
            results['smtp_465'] = "Reachable"
            s.close()
        except Exception as e:
            results['smtp_465'] = f"Unreachable: {str(e)}"
            
        # Test SMTP Port 2525
        try:
            s = socket.create_connection(("smtp.gmail.com", 2525), timeout=5)
            results['smtp_2525'] = "Reachable"
            s.close()
        except Exception as e:
            results['smtp_2525'] = f"Unreachable: {str(e)}"
            
        # Test Firebase API
        api_key = settings.FIREBASE_API_KEY
        if not api_key:
            results['firebase_config'] = "MISSING (FIREBASE_API_KEY is empty)"
        else:
            results['firebase_config'] = f"Present (starts with {api_key[:4]}...)"
            try:
                # Just a simple check to see if the domain is reachable
                r = requests.get("https://identitytoolkit.googleapis.com/generateMobileSdkConfig", timeout=5)
                results['firebase_api_domain'] = f"Reachable ({r.status_code})"
            except Exception as e:
                results['firebase_api_domain'] = f"Unreachable: {str(e)}"
            
        return Response(results)

class SettingsDebugView(APIView):
    permission_classes = [permissions.AllowAny]
    def get(self, request):
        keys = [k for k in dir(settings) if k.isupper()]
        return Response({
            "keys_found": len(keys),
            "livekit_keys": [k for k in keys if "LIVEKIT" in k],
            "deployment_id": getattr(settings, 'DEPLOYMENT_ID', 'NOT_SET'),
            "sample_keys": keys[:10]
        })

class TestEmailView(APIView):
    permission_classes = [permissions.AllowAny]
    
    @swagger_auto_schema(auto_schema=None)
    def post(self, request):
        email = request.data.get('email', 'kbishal177@gmail.com')
        try:
            from django.core.mail import send_mail
            from django.conf import settings
            
            # Print config to response for debugging
            backend = settings.EMAIL_BACKEND
            host = settings.EMAIL_HOST
            user = settings.EMAIL_HOST_USER
            
            print(f"Testing email to {email} using {backend} via {host}")
            
            send_mail(
                "Test Email from Chess App",
                "If you received this, SMTP is working!",
                settings.DEFAULT_FROM_EMAIL,
                [email],
                fail_silently=False,
            )
            return Response({
                "success": True,
                "message": f"Email sent to {email}",
                "config": {
                    "backend": backend,
                    "host": host,
                    "user": user[:3] + "***" if user else "None"
                }
            })
        except Exception as e:
            import traceback
            tb = traceback.format_exc()
            return Response({
                "success": False,
                "message": f"Email Failed: {str(e)}",
                "traceback": tb,
                "config_debug": {
                    "backend": settings.EMAIL_BACKEND,
                    "host": settings.EMAIL_HOST,
                    "user_configured": bool(settings.EMAIL_HOST_USER),
                    "password_configured": bool(settings.EMAIL_HOST_PASSWORD)
                }
            }, status=200)

User = get_user_model()

@api_view(['GET'])
def user_list(request):
    users = User.objects.all().values(
        'id', 'username', 'is_online'
    )
    return Response(users)

class SendOTPView(APIView):
    permission_classes = [permissions.AllowAny]
    
    def post(self, request):
        serializer = EmailSerializer(data=request.data)
        if not serializer.is_valid():
            return Response({
                "success": False,
                "message": "Invalid email format",
                "errors": serializer.errors
            }, status=status.HTTP_400_BAD_REQUEST)
        
        email = serializer.validated_data['email']
        
        try:
            user = User.objects.get(email=email)
        except User.DoesNotExist:
            return Response(
                {
                    "success": False,
                    "message": "No user found with this email address."
                },
                status=status.HTTP_200_OK
            )
        
        try:
            # Generate OTP
            otp_obj = OTP.generate_otp(user, purpose='password_reset')
            
            print(f"Generated OTP: {otp_obj.otp_code} for user: {user.email}")
            
            # For development, print OTP to console
            print(f"DEBUG OTP: {otp_obj.otp_code} (valid for 10 minutes)")
            
            # Try to send email in background
            import threading
            
            def send_otp_email(user, email, otp_code):
                try:
                    # Use standard Django send_mail (uses SMTP settings from settings.py)
                    subject = "Password Reset OTP - Chess Game"
                    html_content = f"""
                    <p>Dear {user.username},</p>
                    <p>Your password reset OTP is: <strong>{otp_code}</strong></p>
                    <p>This OTP will expire in 10 minutes.</p>
                    <p>If you didn't request this, please ignore this email.</p>
                    <p>Best regards,<br>Chess Game Team</p>
                    """
                    
                    plain_message = f"Dear {user.username},\nYour password reset OTP is: {otp_code}\nExpires in 10 minutes."
                    
                    send_mail(
                        subject,
                        plain_message,
                        settings.DEFAULT_FROM_EMAIL,
                        [email],
                        fail_silently=False,
                        html_message=html_content
                    )
                    
                    print(f"✅ Background Email sent via SMTP to {email}")
                except Exception as e:
                    print(f"❌ Background Email sending failed for {email}: {str(e)}")

            # Start background thread
            email_thread = threading.Thread(
                target=send_otp_email,
                args=(user, email, otp_obj.otp_code)
            )
            email_thread.start()
            
            return Response({
                "success": True,
                "message": "OTP generated. Please check your email (and spam folder) in a few moments.",
                "email": email,
                "expires_in": 600
            }, status=status.HTTP_200_OK)
                
        except Exception as e:
            print(f"Error in SendOTPView: {str(e)}")
            return Response({
                "success": False,
                "message": f"Failed to process request: {str(e)}"
            }, status=status.HTTP_200_OK)

class VerifyOTPView(APIView):
    permission_classes = [permissions.AllowAny]
    
    def post(self, request):
        serializer = OTPSerializer(data=request.data)
        if not serializer.is_valid():
            return Response({
                "success": False,
                "message": "Invalid input",
                "errors": serializer.errors
            }, status=status.HTTP_400_BAD_REQUEST)
        
        email = serializer.validated_data['email']
        otp_code = serializer.validated_data['otp']
        
        try:
            user = User.objects.get(email=email)
        except User.DoesNotExist:
            return Response({
                "success": False,
                "message": "Invalid email address."
            }, status=status.HTTP_200_OK)
        
        try:
            otp_obj = OTP.objects.get(
                user=user,
                otp_code=otp_code,
                purpose='password_reset',
                is_used=False
            )
            
            # Check if OTP is expired
            if timezone.now() > otp_obj.expires_at:
                return Response({
                    "success": False,
                    "message": "OTP has expired. Please request a new one."
                }, status=status.HTTP_200_OK)
            
            # Mark OTP as verified (not used yet, will be used when resetting password)
            # otp_obj.mark_used()  # Don't mark used yet, only mark when password is reset
            
            return Response({
                "success": True,
                "message": "OTP verified successfully.",
                "email": email,
                "user_id": user.id
            }, status=status.HTTP_200_OK)
            
        except OTP.DoesNotExist:
            return Response({
                "success": False,
                "message": "Invalid OTP. Please check and try again."
            }, status=status.HTTP_200_OK)
        except Exception as e:
            return Response({
                "success": False,
                "message": f"Verification failed: {str(e)}"
            }, status=status.HTTP_200_OK)

class ResetPasswordView(APIView):
    permission_classes = [permissions.AllowAny]
    
    def post(self, request):
        serializer = PasswordResetSerializer(data=request.data)
        if not serializer.is_valid():
            return Response({
                "success": False,
                "message": "Invalid input",
                "errors": serializer.errors
            }, status=status.HTTP_400_BAD_REQUEST)
        
        email = serializer.validated_data['email']
        otp_code = serializer.validated_data['otp']
        new_password = serializer.validated_data['new_password']
        
        try:
            user = User.objects.get(email=email)
        except User.DoesNotExist:
            return Response({
                "success": False,
                "message": "Invalid email address."
            }, status=status.HTTP_200_OK)
        
        try:
            # Verify OTP one more time
            otp_obj = OTP.objects.get(
                user=user,
                otp_code=otp_code,
                purpose='password_reset',
                is_used=False
            )
            
            if timezone.now() > otp_obj.expires_at:
                return Response({
                    "success": False,
                    "message": "OTP has expired. Please request a new one."
                }, status=status.HTTP_200_OK)
            
            # Update password
            user.set_password(new_password)
            user.save()
            
            # Mark OTP as used
            otp_obj.mark_used()
            
            # Delete all OTPs for this user
            OTP.objects.filter(user=user, purpose='password_reset').delete()
            
            print(f"Password reset successful for {email}")
            
            return Response({
                "success": True,
                "message": "Password reset successfully. You can now login with your new password."
            }, status=status.HTTP_200_OK)
            
        except OTP.DoesNotExist:
            return Response({
                "success": False,
                "message": "Invalid or expired OTP. Please request a new OTP."
            }, status=status.HTTP_200_OK)
        except Exception as e:
            return Response({
                "success": False,
                "message": f"Password reset failed: {str(e)}"
            }, status=status.HTTP_200_OK)


def csrf_failure(request, reason=""):
    """
    Custom CSRF failure view to prove it's our code.
    """
    return JsonResponse({
        "success": False,
        "message": "CSRF_VERIFICATION_FAILED_IDENTIFIED",
        "reason": reason,
        "deployment_id": getattr(settings, 'DEPLOYMENT_ID', 'UNKNOWN'),
        "ts": timezone.now().isoformat()
    }, status=403)

def direct_rollback_check(request):
    return JsonResponse({
        "status": "LIVE_VERSION_CONFIRMED",
        "version": getattr(settings, 'DEPLOYMENT_ID', 'UNKNOWN'),
        "ts": timezone.now().isoformat()
    })

# In-memory registry of rooms that should be recorded when they become active.
# Key: room_id (str), Value: participant count (int)
_rooms_pending_recording: Dict[str, int] = {}

class GetCallTokenView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        room_id = request.query_params.get('room_id')
        should_record = request.query_params.get('record', 'false').lower() == 'true'
        
        if not room_id:
            return Response({'error': 'room_id is required'}, status=400)
        
        if should_record:
            # Mark this room for recording. The actual Egress will be triggered
            # from the webhook once both participants are in the room.
            print(f"📊 [Audit] Room {room_id} marked for archival recording (requested by {request.user.username})")
            _rooms_pending_recording.setdefault(room_id, 0)  # Only initialize if not already tracking
        else:
            print(f"🔒 [Audit] Private session (no recording) for {request.user.username} in room {room_id}")
        
        token = LiveKitService.generate_token(room_id, request.user.username)
        if not token:
            return Response({'error': 'Failed to generate token'}, status=500)
            
        return Response({
            'token': token,
            'url': settings.LIVEKIT_URL
            })


class LiveKitWebhookView(APIView):
    permission_classes = [permissions.AllowAny]
    # Accept both standard JSON AND LiveKit's webhook+json content type
    parser_classes = [WebhookJsonParser, JSONParser]

    def post(self, request):
        # LiveKit sends the actual event data inside a JWT in the Authorization header
        auth_header = request.headers.get('Authorization', '')
        
        if not auth_header:
            print("❌ [LiveKit Webhook] Missing Authorization header")
            return Response({'error': 'Unauthorized'}, status=401)
            
        token = auth_header
        if auth_header.startswith('Bearer '):
            token = auth_header.split(' ')[1]
        
        # Log masked token for debugging
        masked_token = f"{token[:10]}...{token[-10:]}" if len(token) > 20 else "***"
        print(f"📡 [LiveKit Webhook] Auth Attempt - Token: {masked_token}")

        api_secret = getattr(settings, 'LIVEKIT_API_SECRET', 'CEf97PsPDAFW6aVRtmS1NlMid5LQZZ3xWKJyfQPqQ5g')
        
        try:
            # Decode the JWT payload. LiveKit uses HS256.
            # We skip audience/issuer validation here for simplicity, but verify the signature.
            from jose import jwt
            decoded_payload = jwt.decode(token, api_secret, algorithms=['HS256'])
            
            # The decoded payload has an 'event' object inside it if it's a webhook
            # Sometimes LiveKit sends regular JSON body along with auth header if configured via SDK, 
            # but Webhooks are pure JWTs.
            data = decoded_payload.get('event', {}) if 'event' in decoded_payload else request.data
            
        except Exception as e:
            print(f"❌ [LiveKit Webhook] Token decode error: {e}")
            import traceback
            print(f"DEBUG: {traceback.format_exc()}")
            return Response({'error': f'Invalid token: {str(e)}'}, status=401)

        event_type = data.get('event')
        
        print(f"📡 [LiveKit Webhook] Event Received: {event_type}")
        
        if event_type == 'participant_joined':
            room_name = data.get('room', {}).get('name')
            participant = data.get('participant', {})
            identity = participant.get('identity')
            participant_kind = participant.get('kind', 0)
            
            print(f"👤 [LiveKit] Participant '{identity}' (kind: {participant_kind}) joined Room: {room_name}")
            
            # Only count real human participants (kind=0)
            if room_name and participant_kind == 0 and room_name in _rooms_pending_recording:
                _rooms_pending_recording[room_name] = _rooms_pending_recording.get(room_name, 0) + 1
                participant_count = _rooms_pending_recording[room_name]
                
                print(f"📊 [LiveKit] {room_name}: Human Participant Count = {participant_count}")
                
                # Start recording after 2nd participant joins
                if participant_count >= 2:
                    print(f"🎬 [LiveKit] Both participants joined. Triggering recording for {room_name}...")
                    del _rooms_pending_recording[room_name]
                    success = LiveKitService.start_recording(room_name)
                    if success:
                        print(f"✅ [LiveKit] Recording trigger SUCCESS for {room_name}")
                    else:
                        print(f"❌ [LiveKit] Recording trigger FAILED for {room_name}")

        elif event_type == 'egress_started':
            egress = data.get('egress', {})
            # Handle both camelCase and snake_case
            room_name = egress.get('room_name') or egress.get('roomName')
            egress_id = egress.get('egress_id') or egress.get('egressId')
            print(f"🎬 [LiveKit] Egress Started: {egress_id} for Room: {room_name}")

        elif event_type == 'egress_ended':
            egress = data.get('egress', {})
            room_name = egress.get('room_name') or egress.get('roomName')
            egress_id = egress.get('egress_id') or egress.get('egressId')
            status = egress.get('status')
            error = egress.get('error')
            
            print(f"🛑 [LiveKit] Egress Ended: {egress_id} for Room: {room_name}")
            print(f"📊 Status: {status}")
            if error:
                print(f"❌ Error: {error}")
            
            # File results are often in an array called file_results
            file_results = egress.get('file_results', [])
            file_info = file_results[0] if file_results else (egress.get('file') or egress.get('s3') or {})
            
            # Extract location/path
            file_url = file_info.get('location') or file_info.get('key') or file_info.get('filename')
            
            if file_url:
                print(f"📁 Recording saved at: {file_url}")
            else:
                print("⚠️ No recording file location found in webhook data.")
                # Debug print the egress info structure to logs if file not found
                print(f"DEBUG Egress Info: {egress}")

        elif event_type == 'room_finished':
            room_name = data.get('room', {}).get('name')
            if room_name and room_name in _rooms_pending_recording:
                del _rooms_pending_recording[room_name]
                print(f"🧹 [LiveKit] Room {room_name} ended. Cleaned up pending registry.")
            
        return Response({'status': 'ok'})
