from django.urls import path
from .swagger_views import (
    RegisterView, LoginView, LogoutView, 
    SendOTPView, VerifyOTPView, ResetPasswordView,
    SendVerificationEmailView,
    TokenVerifyView, ChangePasswordView,
    GuestRegisterView, HealthCheckView, FirebaseAuthView
)

urlpatterns = [
    # Core Authentication
    path('register/', RegisterView.as_view(), name='register'),
    path('login/', LoginView.as_view(), name='login'),
    path('logout/', LogoutView.as_view(), name='logout'),
    
    # Password Management
    path('send-otp/', SendOTPView.as_view(), name='send_otp'),
    path('verify-otp/', VerifyOTPView.as_view(), name='verify_otp'),
    path('reset-password/', ResetPasswordView.as_view(), name='reset_password'),
    path('change-password/', ChangePasswordView.as_view(), name='change_password'),
    
    # Social & Guest Auth
    path('firebase-login/', FirebaseAuthView.as_view(), name='firebase_login'),
    path('guest/', GuestRegisterView.as_view(), name='guest_register'),
    
    # Email Verification
    path('verify-email/send/', SendVerificationEmailView.as_view(), name='send_verification'),
    path('verify-email/', VerifyEmailTokenView.as_view(), name='verify_email'),
    
    # Token Operations
    path('token/verify/', TokenVerifyView.as_view(), name='verify_token'),
    
    # Health Check
    path('health/', HealthCheckView.as_view(), name='health_check'),
]