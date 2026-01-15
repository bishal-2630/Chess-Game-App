from rest_framework import status, permissions
from rest_framework.response import Response
from rest_framework.views import APIView
from django.contrib.auth import get_user_model
from django.core.mail import send_mail
from django.conf import settings
from django.utils import timezone
import json
import requests

from .models import OTP
from .serializers import (
    EmailSerializer, 
    OTPSerializer, 
    PasswordResetSerializer,
    FirebaseAuthSerializer
)

class ConnectivityCheckView(APIView):
    permission_classes = [permissions.AllowAny]
    
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
            
        return Response(results)

User = get_user_model()

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
                    subject = "Password Reset OTP - Chess Game"
                    message = f"""
Dear {user.username},

Your password reset OTP is: {otp_code}

This OTP will expire in 10 minutes.

If you didn't request this, please ignore this email.

Best regards,
Chess Game Team
"""
                    send_mail(
                        subject=subject,
                        message=message,
                        from_email=settings.DEFAULT_FROM_EMAIL,
                        recipient_list=[email],
                        fail_silently=False,
                    )
                    print(f"✅ Background Email sent successfully to {email}")
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
        
        

class FirebaseAuthView(APIView):
    permission_classes = [permissions.AllowAny]
    
    def post(self, request):
        serializer = FirebaseAuthSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
        
        firebase_token = serializer.validated_data['firebase_token']
        
        try:
            print(f"DEBUG: Verifying Firebase token...")
            # Verify Firebase token using Firebase REST API
            api_key = settings.FIREBASE_API_KEY
            verify_url = f"https://identitytoolkit.googleapis.com/v1/accounts:lookup?key={api_key}"
            
            response = requests.post(verify_url, json={"idToken": firebase_token}, timeout=10)
            response_data = response.json()
            
            if response.status_code != 200:
                print(f"DEBUG: Firebase token verification failed: {response_data}")
                return Response(
                    {"detail": "Invalid Firebase token."},
                    status=status.HTTP_401_UNAUTHORIZED
                )
            
            user_info = response_data['users'][0]
            firebase_uid = user_info['localId']
            email = user_info.get('email')
            display_name = user_info.get('displayName', '')
            
            print(f"DEBUG: User Info from Firebase: UID={firebase_uid}, Email={email}")
            
            if not email:
                return Response(
                    {"detail": "Email not found in Firebase token."},
                    status=status.HTTP_400_BAD_REQUEST
                )
            
            # Get or create user
            try:
                user = User.objects.get(firebase_uid=firebase_uid)
                print(f"DEBUG: Found user by UID: {user.username}")
            except User.DoesNotExist:
                try:
                    user = User.objects.get(email=email)
                    user.firebase_uid = firebase_uid
                    user.save()
                    print(f"DEBUG: found user by email and updated UID: {user.username}")
                except User.DoesNotExist:
                    print(f"DEBUG: Creating new user for: {email}")
                    # Create username from email
                    username = email.split('@')[0]
                    base_username = username
                    counter = 1
                    
                    # Ensure unique username
                    while User.objects.filter(username=username).exists():
                        username = f"{base_username}{counter}"
                        counter += 1
                    
                    # Parse display name
                    first_name = ''
                    last_name = ''
                    if display_name:
                        name_parts = display_name.split()
                        if len(name_parts) > 0:
                            first_name = name_parts[0]
                        if len(name_parts) > 1:
                            last_name = ' '.join(name_parts[1:])
                    
                    user = User.objects.create_user(
                        username=username,
                        email=email,
                        password=None,  # Firebase users don't have Django passwords
                        first_name=first_name,
                        last_name=last_name,
                        firebase_uid=firebase_uid
                    )
            
            # Login the user to create a session and sessionid cookie
            print(f"DEBUG: Attempting session login for user: {user.username}")
            from django.contrib.auth import login
            if user is not None:
                # Specify the backend manually since we didn't use authenticate()
                user.backend = 'django.contrib.auth.backends.ModelBackend'
                login(request, user)
                print(f"DEBUG: Session login successful for user: {user.username}")
            
            # Generate JWT token for Django API access
            from rest_framework_simplejwt.tokens import RefreshToken
            
            print(f"DEBUG: Generating JWT token for user: {user.username}")
            refresh = RefreshToken.for_user(user)
            
            return Response({
                "access": str(refresh.access_token),
                "refresh": str(refresh),
                "user": {
                    "id": user.id,
                    "username": user.username,
                    "email": user.email,
                    "first_name": user.first_name,
                    "last_name": user.last_name,
                    "firebase_uid": user.firebase_uid
                }
            }, status=status.HTTP_200_OK)
            
        except Exception as e:
            import traceback
            error_traceback = traceback.format_exc()
            print(f"ERROR in FirebaseAuthView: {str(e)}")
            print(error_traceback)
            return Response(
                {
                    "detail": f"Authentication failed: {str(e)}",
                    "traceback": error_traceback
                },
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )