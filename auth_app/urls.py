from django.urls import path
from .views import (
    SendOTPView,
    VerifyOTPView,
    ResetPasswordView,
    FirebaseAuthView
)

# Check if swagger_views exists
try:
    from .swagger_views import HealthCheckView
    HAS_SWAGGER = True
except ImportError:
    HAS_SWAGGER = False
    # Create simple health check
    from rest_framework.views import APIView
    from rest_framework.response import Response
    from rest_framework.permissions import AllowAny
    from django.utils import timezone
    
    class HealthCheckView(APIView):
        permission_classes = [AllowAny]
        
        def get(self, request):
            return Response({
                'status': 'healthy',
                'service': 'Chess Game Authentication API',
                'owner': 'Bishal',
                'timestamp': timezone.now().isoformat(),
                'endpoints': {
                    'send_otp': '/api/auth/send-otp/',
                    'verify_otp': '/api/auth/verify-otp/',
                    'reset_password': '/api/auth/reset-password/',
                    'firebase_login': '/api/auth/firebase-login/',
                    'swagger': '/swagger/'
                }
            })

urlpatterns = [
    # Your existing real endpoints (from views.py)
    path('send-otp/', SendOTPView.as_view(), name='send_otp'),
    path('verify-otp/', VerifyOTPView.as_view(), name='verify_otp'),
    path('reset-password/', ResetPasswordView.as_view(), name='reset_password'),
    path('firebase-login/', FirebaseAuthView.as_view(), name='firebase_login'),
    
    # Health check
    path('health/', HealthCheckView.as_view(), name='health_check'),
]

# Add demo endpoints if swagger_views exists
if HAS_SWAGGER:
    from .swagger_views import (
        RegisterView, LoginView, LogoutView, GoogleAuthView,
        SendVerificationEmailView, TokenVerifyView, TokenRefreshView,
        ChangePasswordView, GuestRegisterView
    )
    
    urlpatterns += [
        path('register/', RegisterView.as_view(), name='register'),
        path('login/', LoginView.as_view(), name='login'),
        path('logout/', LogoutView.as_view(), name='logout'),
        path('google/', GoogleAuthView.as_view(), name='google_auth'),
        path('verify-email/send/', SendVerificationEmailView.as_view(), name='send_verification'),
        path('token/verify/', TokenVerifyView.as_view(), name='verify_token'),
        path('token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
        path('change-password/', ChangePasswordView.as_view(), name='change_password'),
        path('guest/', GuestRegisterView.as_view(), name='guest_register'),
    ]
