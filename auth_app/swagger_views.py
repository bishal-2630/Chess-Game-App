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
from .serializers import FirebaseAuthSerializer

User = get_user_model()

# ========== REGISTRATION ==========
class RegisterView(APIView):
    """
    Register a new user with email, username and password
    """
    permission_classes = [AllowAny]
    
    @swagger_auto_schema(
        request_body=openapi.Schema(
            type=openapi.TYPE_OBJECT,
            required=['email', 'password', 'username'],
            properties={
                'username': openapi.Schema(
                    type=openapi.TYPE_STRING, 
                    description='Unique username (min 3 chars, no spaces)'
                ),
                'email': openapi.Schema(
                    type=openapi.TYPE_STRING, 
                    description='Valid email address'
                ),
                'password': openapi.Schema(
                    type=openapi.TYPE_STRING, 
                    description='Password (min 6 characters)'
                ),
            }
        ),
        responses={
            201: openapi.Response(
                'User registered successfully', 
                examples={
                    'application/json': {
                        'success': True,
                        'user': {
                            'id': 1,
                            'username': 'testuser',
                            'email': 'test@example.com'
                        },
                        'tokens': {
                            'access': 'eyJhbGciOi...',
                            'refresh': 'eyJhbGciOi...'
                        }
                    }
                }
            ),
            400: openapi.Response(
                'Bad Request',
                examples={
                    'application/json': {
                        'success': False,
                        'message': 'Email already exists'
                    }
                }
            )
        }
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
        
        if User.objects.filter(email=email).exists():
            return Response({
                'success': False,
                'message': 'Email already exists'
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
            user = User(
                username=username,
                email=email,
                is_active=True
            )
            user.set_password(password)  
            user.save()
            
            # Generate JWT tokens
            refresh = RefreshToken.for_user(user)
            
            return Response({
                'success': True,
                'message': 'User registered successfully',
                'user': {
                    'id': user.id,
                    'username': user.username,
                    'email': user.email
                },
                'tokens': {
                    'access': str(refresh.access_token),
                    'refresh': str(refresh)
                }
            }, status=status.HTTP_201_CREATED)
            
        except Exception as e:
            return Response({
                'success': False,
                'message': f'Registration failed: {str(e)}'
            }, status=status.HTTP_400_BAD_REQUEST)


# ========== LOGIN ==========
class LoginView(APIView):
    """
    Login with email and password
    """
    permission_classes = [AllowAny]
    
    @swagger_auto_schema(
        request_body=openapi.Schema(
            type=openapi.TYPE_OBJECT,
            required=['email', 'password'],
            properties={
                'email': openapi.Schema(
                    type=openapi.TYPE_STRING, 
                    description='Registered email address'
                ),
                'password': openapi.Schema(
                    type=openapi.TYPE_STRING, 
                    description='Account password'
                ),
            }
        ),
        responses={
            200: openapi.Response(
                'Login successful',
                examples={
                    'application/json': {
                        'success': True,
                        'user': {
                            'id': 1,
                            'username': 'testuser',
                            'email': 'test@example.com'
                        },
                        'tokens': {
                            'access': 'eyJhbGciOi...',
                            'refresh': 'eyJhbGciOi...'
                        }
                    }
                }
            ),
            401: openapi.Response(
                'Invalid credentials',
                examples={
                    'application/json': {
                        'success': False,
                        'message': 'Invalid credentials'
                    }
                }
            )
        }
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
        
        # Try to authenticate
        user = authenticate(username=email, password=password)
        
        if user is None:
            # Check if user exists but password is wrong
            if User.objects.filter(email=email).exists():
                return Response({
                    'success': False,
                    'message': 'Invalid password'
                }, status=status.HTTP_401_UNAUTHORIZED)
            else:
                return Response({
                    'success': False,
                    'message': 'No account found with this email'
                }, status=status.HTTP_401_UNAUTHORIZED)
        
        # Generate JWT tokens
        refresh = RefreshToken.for_user(user)
        
        return Response({
            'success': True,
            'message': 'Login successful',
            'user': {
                'id': user.id,
                'username': user.username,
                'email': user.email,
                'email_verified': user.email_verified
            },
            'tokens': {
                'access': str(refresh.access_token),
                'refresh': str(refresh)
            }
        }, status=status.HTTP_200_OK)


# ========== LOGOUT ==========
class LogoutView(APIView):
    """
    Logout user and blacklist refresh token
    """
    permission_classes = [IsAuthenticated]
    
    @swagger_auto_schema(
        request_body=openapi.Schema(
            type=openapi.TYPE_OBJECT,
            required=['refresh'],
            properties={
                'refresh': openapi.Schema(
                    type=openapi.TYPE_STRING, 
                    description='Refresh token to blacklist'
                ),
            }
        ),
        responses={
            200: openapi.Response(
                'Logged out successfully',
                examples={
                    'application/json': {
                        'success': True,
                        'message': 'Successfully logged out'
                    }
                }
            ),
            400: openapi.Response(
                'Invalid token',
                examples={
                    'application/json': {
                        'success': False,
                        'message': 'Invalid refresh token'
                    }
                }
            )
        }
    )
    def post(self, request):
        """Logout user and blacklist refresh token"""
        try:
            refresh_token = request.data.get('refresh')
            
            if not refresh_token:
                return Response({
                    'success': False,
                    'message': 'Refresh token is required'
                }, status=status.HTTP_400_BAD_REQUEST)
            
            # Blacklist the refresh token
            token = RefreshToken(refresh_token)
            token.blacklist()
            
            return Response({
                'success': True,
                'message': 'Successfully logged out'
            }, status=status.HTTP_200_OK)
            
        except TokenError as e:
            return Response({
                'success': False,
                'message': f'Invalid token: {str(e)}'
            }, status=status.HTTP_400_BAD_REQUEST)
        except Exception as e:
            return Response({
                'success': False,
                'message': str(e)
            }, status=status.HTTP_400_BAD_REQUEST)




# ========== EMAIL VERIFICATION ==========
class SendVerificationEmailView(APIView):
    """
    Send email verification link to user
    """
    permission_classes = [IsAuthenticated]
    
    @swagger_auto_schema(
        responses={
            200: openapi.Response(
                'Verification email sent',
                examples={
                    'application/json': {
                        'success': True,
                        'message': 'Verification email sent'
                    }
                }
            ),
            400: openapi.Response(
                'Email already verified',
                examples={
                    'application/json': {
                        'success': False,
                        'message': 'Email already verified'
                    }
                }
            )
        }
    )
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
    
    @swagger_auto_schema(
        manual_parameters=[
            openapi.Parameter(
                'token',
                openapi.IN_QUERY,
                description="Email verification token",
                type=openapi.TYPE_STRING,
                required=True
            ),
            openapi.Parameter(
                'user_id',
                openapi.IN_QUERY,
                description="User ID to verify",
                type=openapi.TYPE_INTEGER,
                required=True
            )
        ],
        responses={
            200: openapi.Response(
                'Email verified successfully',
                examples={
                    'application/json': {
                        'success': True,
                        'message': 'Email verified successfully'
                    }
                }
            ),
            400: openapi.Response(
                'Invalid or expired token',
                examples={
                    'application/json': {
                        'success': False,
                        'message': 'Invalid or expired verification token'
                    }
                }
            )
        }
    )
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
                'token': openapi.Schema(
                    type=openapi.TYPE_STRING, 
                    description='JWT access token to verify'
                ),
            }
        ),
        responses={
            200: openapi.Response(
                'Token is valid',
                examples={
                    'application/json': {
                        'valid': True,
                        'message': 'Token is valid'
                    }
                }
            ),
            401: openapi.Response(
                'Token is invalid',
                examples={
                    'application/json': {
                        'valid': False,
                        'message': 'Token is invalid or expired'
                    }
                }
            )
        }
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
        request_body=openapi.Schema(
            type=openapi.TYPE_OBJECT,
            required=['username'],
            properties={
                'username': openapi.Schema(
                    type=openapi.TYPE_STRING, 
                    description='Guest username'
                ),
            }
        ),
        responses={
            200: openapi.Response(
                'Guest session created',
                examples={
                    'application/json': {
                        'success': True,
                        'message': 'Guest session created',
                        'guest_user': {
                            'id': 999,
                            'username': 'GuestPlayer123',
                            'is_guest': True
                        },
                        'tokens': {
                            'access': 'eyJhbGciOi...',
                            'refresh': 'eyJhbGciOi...'
                        }
                    }
                }
            )
        }
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
    
    @swagger_auto_schema(
        responses={
            200: openapi.Response(
                'API is healthy',
                examples={
                    'application/json': {
                        'status': 'healthy',
                        'timestamp': '2024-01-01T12:00:00Z',
                        'version': '1.0.0',
                        'database': 'connected'
                    }
                }
            )
        }
    )
    def get(self, request):
        """Health check endpoint"""
        from django.db import connection
        
        # Check database connection
        db_status = 'connected'
        try:
            connection.ensure_connection()
        except:
            db_status = 'disconnected'
        
        return Response({
            'status': 'healthy',
            'timestamp': timezone.now().isoformat(),
            'service': 'Chess Game Authentication API',
            'version': '1.0.0',
            'database': db_status,
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
        request_body=openapi.Schema(
            type=openapi.TYPE_OBJECT,
            required=['email'],
            properties={
                'email': openapi.Schema(
                    type=openapi.TYPE_STRING, 
                    description='User email address'
                ),
            }
        ),
        responses={
            200: openapi.Response('OTP sent successfully'),
            400: openapi.Response('User not found')
        }
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
            
            # Try to send email
            try:
                subject = "Password Reset OTP - Chess Game"
                message = f"Your OTP for password reset is: {otp_obj.otp_code}\n\nThis OTP will expire in 10 minutes."
                
                send_mail(
                    subject=subject,
                    message=message,
                    from_email=settings.DEFAULT_FROM_EMAIL,
                    recipient_list=[email],
                    fail_silently=False,
                )
                
                return Response({
                    'success': True,
                    'message': f'OTP sent to {email}',
                    'expires_in': 600  # 10 minutes
                }, status=status.HTTP_200_OK)
                
            except Exception as email_error:
                # If email fails, fallback to console and include debug OTP
                print(f"Email sending failed: {str(email_error)}")
                print(f"OTP for {email}: {otp_obj.otp_code}")
                
                return Response({
                    'success': True,
                    'message': f'OTP generated but email failed: {str(email_error)}',
                    'debug_otp': otp_obj.otp_code,  # For debugging only
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
        request_body=openapi.Schema(
            type=openapi.TYPE_OBJECT,
            required=['email', 'otp'],
            properties={
                'email': openapi.Schema(type=openapi.TYPE_STRING),
                'otp': openapi.Schema(type=openapi.TYPE_STRING),
            }
        ),
        responses={200: 'OTP verified', 400: 'Invalid OTP'}
    )
    def post(self, request):
        email = request.data.get('email')
        otp_code = request.data.get('otp')
        
        try:
            user = User.objects.get(email=email)
            from .models import OTP
            from django.utils import timezone
            
            otp_obj = OTP.objects.get(
                user=user,
                otp_code=otp_code,
                purpose='password_reset',
                is_used=False
            )
            
            if timezone.now() > otp_obj.expires_at:
                return Response({
                    'success': False,
                    'message': 'OTP expired'
                })
            
            return Response({
                'success': True,
                'message': 'OTP verified successfully'
            })
            
        except (User.DoesNotExist, OTP.DoesNotExist):
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
        request_body=openapi.Schema(
            type=openapi.TYPE_OBJECT,
            required=['email', 'otp', 'new_password', 'confirm_password'],
            properties={
                'email': openapi.Schema(type=openapi.TYPE_STRING),
                'otp': openapi.Schema(type=openapi.TYPE_STRING),
                'new_password': openapi.Schema(type=openapi.TYPE_STRING),
                'confirm_password': openapi.Schema(type=openapi.TYPE_STRING),
            }
        ),
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
            from django.utils import timezone
            
            otp_obj = OTP.objects.get(
                user=user,
                otp_code=otp_code,
                purpose='password_reset',
                is_used=False
            )
            
            if timezone.now() > otp_obj.expires_at:
                return Response({
                    'success': False,
                    'message': 'OTP expired'
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
            
        except (User.DoesNotExist, OTP.DoesNotExist):
            return Response({
                'success': False,
                'message': 'Invalid OTP or email'
            })


# ========== FIREBASE AUTH ==========
class FirebaseAuthView(APIView):
    """
    Firebase authentication and session synchronization
    """
    permission_classes = [AllowAny]
    
    @swagger_auto_schema(
        request_body=FirebaseAuthSerializer,
        responses={
            200: openapi.Response(
                'Authentication successful',
                examples={
                    'application/json': {
                        'access': 'eyJhbGciOi...',
                        'refresh': 'eyJhbGciOi...',
                        'user': {
                            'id': 1,
                            'username': 'bishal',
                            'email': 'kbishal177@gmail.com'
                        }
                    }
                }
            ),
            401: openapi.Response('Invalid Firebase token')
        }
    )
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
            
            response = requests.post(verify_url, json={"idToken": firebase_token})
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
