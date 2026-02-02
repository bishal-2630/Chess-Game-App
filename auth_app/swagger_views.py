from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.exceptions import TokenError
from django.contrib.auth import authenticate, get_user_model
from django.utils import timezone
from drf_yasg.utils import swagger_auto_schema
from drf_yasg import openapi
from django.core.mail import send_mail
from django.conf import settings
import pyotp
import requests
import traceback
from .serializers import (
    RegisterSerializer, LoginSerializer, LogoutSerializer, 
    UserSerializer, TokenSerializer, AuthResponseSerializer,
    GuestRegisterSerializer, EmailSerializer, OTPSerializer,
    PasswordResetSerializer
)

User = get_user_model()

# ========== REGISTRATION ==========
class RegisterView(APIView):
    """
    Register a new user with email, username and password
    """
    permission_classes = [AllowAny]
    
    @swagger_auto_schema(
        request_body=RegisterSerializer,
        responses={201: AuthResponseSerializer, 400: 'Bad Request'}
    )
    def post(self, request):
        """Register a new user"""
        email = request.data.get('email')
        password = request.data.get('password')
        username = request.data.get('username')
        
        # Validation
        if not email or not password or not username:
            return Response({
                'success': False,
                'message': 'Email, password and username are required'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        if User.objects.filter(email__iexact=email).exists():
            return Response({
                'success': False,
                'message': 'An account with this email already exists'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        if User.objects.filter(username=username).exists():
            return Response({
                'success': False,
                'message': 'Username already exists'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        if len(username) < 3:
            return Response({
                'success': False,
                'message': 'Username must be at least 3 characters'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        if ' ' in username:
            return Response({
                'success': False,
                'message': 'Username cannot contain spaces'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        if len(password) < 6:
            return Response({
                'success': False,
                'message': 'Password must be at least 6 characters'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        try:
            # Use create_user to handle hashing and normalization automatically
            user = User.objects.create_user(
                username=username,
                email=email,
                password=password
            )
            # user.is_active = True # create_user defaults to True usually, but safe to assume handling elsewhere or default model
            print(f"User registered: {username}")
            
            # Generate JWT tokens
            refresh = RefreshToken.for_user(user)
            
            return Response({
                'success': True,
                'message': 'User registered successfully',
                'user': {
                    'id': user.id,
                    'username': user.username,
                    'email': user.email,
                    'first_name': user.first_name,
                    'last_name': user.last_name,
                    'profile_picture': user.profile_picture,
                    'email_verified': user.email_verified,
                    'is_online': user.is_online,
                    'last_seen': user.last_seen.isoformat() if user.last_seen else None,
                    'current_room': user.current_room
                },
                'tokens': {
                    'access': str(refresh.access_token),
                    'refresh': str(refresh)
                }
            }, status=status.HTTP_201_CREATED)
            
        except Exception as e:
            print(f"Registration Error: {str(e)}")
            traceback.print_exc()
            return Response({
                'success': False,
                'message': f'Registration failed: {str(e)}',
                'traceback': traceback.format_exc()
            }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ========== LOGIN ==========
class LoginView(APIView):
    """
    Login with email and password
    """
    permission_classes = [AllowAny]
    
    @swagger_auto_schema(
        request_body=LoginSerializer,
        responses={200: AuthResponseSerializer, 401: 'Invalid credentials'}
    )
    def post(self, request):
        """Login with email and password"""
        email = request.data.get('email')
        password = request.data.get('password')
        
        if not email or not password:
            return Response({
                'success': False,
                'message': 'Email and password are required'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        try:
            # Try to find user by email first
            try:
                user = User.objects.get(email=email)
                print(f"Found user: {user.username}, id={user.id}")
            except User.DoesNotExist:
                print(f"No user found with email: {email}")
                return Response({
                    'success': False,
                    'message': 'No account found with this email'
                }, status=status.HTTP_401_UNAUTHORIZED)
            
            # Check password
            if not user.check_password(password):
                print(f"Password check failed for user {user.username}")
                return Response({
                    'success': False,
                    'message': 'Invalid password'
                }, status=status.HTTP_401_UNAUTHORIZED)
            
            print(f"Password check passed for user {user.username}")
            
            # Generate JWT tokens
            refresh = RefreshToken.for_user(user)
            
            return Response({
                'success': True,
                'message': 'Login successful',
                'user': {
                    'id': user.id,
                    'username': user.username,
                    'email': user.email,
                    'email_verified': user.email_verified,
                    'first_name': user.first_name,
                    'last_name': user.last_name,
                    'profile_picture': user.profile_picture,
                    'is_online': user.is_online,
                    'last_seen': user.last_seen.isoformat() if user.last_seen else None,
                    'current_room': user.current_room
                },
                'tokens': {
                    'access': str(refresh.access_token),
                    'refresh': str(refresh)
                }
            }, status=status.HTTP_200_OK)
        except Exception as e:
            print(f"Login Error: {str(e)}")
            traceback.print_exc()
            return Response({
                'success': False,
                'message': f'Login failed: {str(e)}',
                'traceback': traceback.format_exc()
            }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ========== LOGOUT ==========
class LogoutView(APIView):
    """
    Logout user and blacklist refresh token
    """
    permission_classes = [AllowAny]
    
    @swagger_auto_schema(
        request_body=LogoutSerializer,
        responses={200: 'Logged out successfully'}
    )
    def post(self, request):
        """Logout user and blacklist refresh token"""
        try:
            refresh_token = request.data.get('refresh')
            
            if refresh_token:
                # Blacklist the refresh token if provided
                token = RefreshToken(refresh_token)
                token.blacklist()
            
            return Response({
                'success': True,
                'message': 'Successfully logged out'
            }, status=status.HTTP_200_OK)
            
        except Exception as e:
            # Even if it fails (e.g. token expired), we still return 200 
            # because the user's intent was to logout and the token is no longer valid anyway
            return Response({
                'success': True, 
                'message': 'Successfully logged out (session already cleared)'
            }, status=status.HTTP_200_OK)




# ========== EMAIL VERIFICATION ==========
class SendVerificationEmailView(APIView):
    """
    Send email verification link to user
    """
    permission_classes = [IsAuthenticated]
    
    @swagger_auto_schema(auto_schema=None)
    def post(self, request):
        """Send email verification link"""
        user = request.user
        
        # Check if already verified
        if user.email_verified:
            return Response({
                'success': False,
                'message': 'Email already verified'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        # For Termux demo - simulate email sending
        # In production, implement actual email sending
        
        # Generate verification token (simulated)
        verification_token = pyotp.random_base32()[:20]
        
        # In production, you would:
        # 1. Generate a secure token
        # 2. Send email with verification link
        # 3. Store token in database with expiry
        
        return Response({
            'success': True,
            'message': 'Verification email sent (demo mode)',
            'debug_info': {
                'user_id': user.id,
                'email': user.email,
                'demo_token': verification_token,
                'note': 'In production, implement actual email sending'
            }
        }, status=status.HTTP_200_OK)


# ========== VERIFY EMAIL TOKEN ==========
class VerifyEmailTokenView(APIView):
    """
    Verify email using token from verification link
    """
    permission_classes = [AllowAny]
    
    @swagger_auto_schema(auto_schema=None)
    def get(self, request):
        """Verify email using token (GET request for email links)"""
        token = request.GET.get('token')
        user_id = request.GET.get('user_id')
        
        if not token or not user_id:
            return Response({
                'success': False,
                'message': 'Token and user_id are required'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        try:
            user = User.objects.get(id=user_id)
            
            # For demo - accept any token
            # In production, verify token against stored hash with expiry
            
            if user.email_verified:
                return Response({
                    'success': True,
                    'message': 'Email already verified'
                }, status=status.HTTP_200_OK)
            
            # Mark email as verified
            user.email_verified = True
            user.save()
            
            return Response({
                'success': True,
                'message': 'Email verified successfully (demo)',
                'user': {
                    'id': user.id,
                    'email': user.email,
                    'email_verified': user.email_verified
                },
                'note': 'In production, implement proper token verification'
            }, status=status.HTTP_200_OK)
            
        except User.DoesNotExist:
            return Response({
                'success': False,
                'message': 'User not found'
            }, status=status.HTTP_400_BAD_REQUEST)
        except Exception as e:
            return Response({
                'success': False,
                'message': f'Verification failed: {str(e)}'
            }, status=status.HTTP_400_BAD_REQUEST)


# ========== TOKEN VERIFY ==========
class TokenVerifyView(APIView):
    """
    Verify if a JWT token is valid
    """
    permission_classes = [AllowAny]
    
    @swagger_auto_schema(
        request_body=openapi.Schema(
            type=openapi.TYPE_OBJECT,
            required=['token'],
            properties={
                'token': openapi.Schema(type=openapi.TYPE_STRING, description='Token to verify'),
            }
        ),
        responses={200: 'Token is valid', 401: 'Token is invalid'}
    )
    def post(self, request):
        """Verify JWT token"""
        token = request.data.get('token')
        
        if not token:
            return Response({
                'valid': False,
                'message': 'Token is required'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        try:
            # Verify the token
            access_token = RefreshToken(token).access_token
            
            # Check if token is expired
            from rest_framework_simplejwt.tokens import AccessToken
            AccessToken(token)
            
            return Response({
                'valid': True,
                'message': 'Token is valid',
                'exp': access_token['exp'] if 'exp' in access_token else None
            }, status=status.HTTP_200_OK)
            
        except TokenError as e:
            return Response({
                'valid': False,
                'message': f'Token error: {str(e)}'
            }, status=status.HTTP_401_UNAUTHORIZED)
        except Exception as e:
            return Response({
                'valid': False,
                'message': f'Invalid token: {str(e)}'
            }, status=status.HTTP_401_UNAUTHORIZED)


# ========== GUEST REGISTRATION (for your Flutter app) ==========
class GuestRegisterView(APIView):
    """
    Create a guest user session
    """
    permission_classes = [AllowAny]
    
    @swagger_auto_schema(
        request_body=GuestRegisterSerializer,
        responses={200: AuthResponseSerializer}
    )
    def post(self, request):
        """Create a guest user session"""
        username = request.data.get('username')
        
        if not username:
            return Response({
                'success': False,
                'message': 'Username is required'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        # Generate unique guest username
        guest_username = f"Guest_{username}_{int(timezone.now().timestamp())}"
        
        try:
            # Create guest user (no password, no email)
            user = User.objects.create_user(
                username=guest_username,
                email=f"{guest_username}@guest.chessgame",
                password=None  # No password for guest
            )
            
            # Mark as guest user
            user.set_unusable_password()
            user.save()
            
            # Generate JWT tokens
            refresh = RefreshToken.for_user(user)
            
            return Response({
                'success': True,
                'message': 'Guest session created',
                'guest_user': {
                    'id': user.id,
                    'username': guest_username,
                    'is_guest': True
                },
                'tokens': {
                    'access': str(refresh.access_token),
                    'refresh': str(refresh)
                },
                'note': 'Guest sessions are temporary and may be cleaned up periodically'
            }, status=status.HTTP_200_OK)
            
        except Exception as e:
            return Response({
                'success': False,
                'message': f'Guest registration failed: {str(e)}'
            }, status=status.HTTP_400_BAD_REQUEST)


# ========== HEALTH CHECK ==========
class HealthCheckView(APIView):
    """
    Health check endpoint for API monitoring
    """
    permission_classes = [AllowAny]
    
    @swagger_auto_schema(auto_schema=None)
    def get(self, request):
        from django.db import connection
        
        # Check database connection
        db_status = 'connected'
        try:
            connection.ensure_connection()
        except:
            db_status = 'disconnected'
        
        return Response({
            'status': 'healthy',
            'deploy_version': 'v3-forced-update-2026-01-19-try2', # Tracer bullet force update
            'timestamp': timezone.now().isoformat(),
            'service': 'Chess Game Authentication API',
            'version': '1.0.0',
            'database': db_status,
            'debug_bypass_deployed': True,
            'endpoints': {
                'register': '/api/auth/register/',
                'login': '/api/auth/login/',
                'logout': '/api/auth/logout/',
                'send_otp': '/api/auth/send-otp/',
                'verify_otp': '/api/auth/verify-otp/',
                'reset_password': '/api/auth/reset-password/',
                'swagger': '/swagger/',
                'redoc': '/redoc/'
            }
        }, status=status.HTTP_200_OK)
    

class DebugPasswordView(APIView):
    """
    Debug password verification
    """
    permission_classes = [IsAuthenticated]
    
    def post(self, request):
        password_to_check = request.data.get('password', '')
        user = request.user
        
        return Response({
            'user_id': user.id,
            'email': user.email,
            'username': user.username,
            'password_provided': password_to_check,
            'password_matches': user.check_password(password_to_check),
            'has_usable_password': user.has_usable_password(),
            'password_hash_preview': user.password[:50] + '...' if user.password else 'None'
        })
    

# ========== SEND OTP ==========
class SendOTPView(APIView):
    """
    Send OTP for password reset
    """
    permission_classes = [AllowAny]
    
    @swagger_auto_schema(
        request_body=EmailSerializer,
        responses={200: 'OTP sent successfully', 400: 'Bad Request'}
    )
    def post(self, request):
        email = request.data.get('email')
        
        if not email:
            return Response({
                'success': False,
                'message': 'Email is required'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        try:
            user = User.objects.get(email=email)
            
            # Generate OTP (using your OTP model)
            from .models import OTP
            otp_obj = OTP.generate_otp(user, purpose='password_reset')
            
            # CLEAR LOG FOR USER
            print(f"\n🚀 [OTP FOR {email}]: {otp_obj.otp_code} 🚀\n")
            
            # Try to send email in background
            import threading
            from .models import OTP
            
            # Start background thread to send OTP
            email_thread = threading.Thread(
                target=otp_obj.send_otp
            )
            email_thread.daemon = True
            email_thread.start()
            
            return Response({
                'success': True,
                'message': f'OTP generated. Please check your email (and spam folder) in a few moments.',
                'expires_in': 600
            }, status=status.HTTP_200_OK)
            
        except User.DoesNotExist:
            return Response({
                'success': False,
                'message': 'No user found with this email'
            }, status=status.HTTP_200_OK)
        except Exception as e:
            return Response({
                'success': False,
                'message': f'Error: {str(e)}'
            }, status=status.HTTP_400_BAD_REQUEST)


# ========== VERIFY OTP ==========
class VerifyOTPView(APIView):
    """
    Verify OTP for password reset
    """
    permission_classes = [AllowAny]
    
    @swagger_auto_schema(
        request_body=OTPSerializer,
        responses={200: 'OTP verified', 400: 'Invalid OTP'}
    )
    def post(self, request):
        email = request.data.get('email')
        otp_code = request.data.get('otp')
        
        try:
            user = User.objects.get(email=email)
            from .models import OTP
            
            # Find the most recent unused OTP for this user
            otp_obj = OTP.objects.filter(
                user=user,
                purpose='password_reset',
                is_used=False
            ).order_by('-created_at').first()
            
            if not otp_obj or not otp_obj.is_valid(otp_code):
                return Response({
                    'success': False,
                    'message': 'Invalid or expired OTP'
                })
            
            return Response({
                'success': True,
                'message': 'OTP verified successfully'
            })
            
        except User.DoesNotExist:
            return Response({
                'success': False,
                'message': 'Invalid OTP or email'
            })


# ========== RESET PASSWORD ==========
class ResetPasswordView(APIView):
    """
    Reset password using verified OTP
    """
    permission_classes = [AllowAny]
    
    @swagger_auto_schema(
        request_body=PasswordResetSerializer,
        responses={200: 'Password reset', 400: 'Reset failed'}
    )
    def post(self, request):
        email = request.data.get('email')
        otp_code = request.data.get('otp')
        new_password = request.data.get('new_password')
        confirm_password = request.data.get('confirm_password')
        
        if new_password != confirm_password:
            return Response({
                'success': False,
                'message': 'Passwords do not match'
            })
        
        if len(new_password) < 6:
            return Response({
                'success': False,
                'message': 'Password must be at least 6 characters'
            })
        
        try:
            user = User.objects.get(email=email)
            from .models import OTP
            
            # Find the most recent unused OTP for this user
            otp_obj = OTP.objects.filter(
                user=user,
                purpose='password_reset',
                is_used=False
            ).order_by('-created_at').first()
            
            if not otp_obj or not otp_obj.is_valid(otp_code):
                return Response({
                    'success': False,
                    'message': 'Invalid or expired OTP'
                })
            
            # Update password
            user.set_password(new_password)
            user.save()
            
            # Mark OTP as used
            otp_obj.mark_used()
            
            return Response({
                'success': True,
                'message': 'Password reset successfully'
            })
            
        except User.DoesNotExist:
            return Response({
                'success': False,
                'message': 'Invalid OTP or email'
            })


from django.utils.decorators import method_decorator
from django.views.decorators.csrf import csrf_exempt

# Bypass views removed for security.

