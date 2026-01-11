from django.urls import path
from .views import (
    SendOTPView,
    VerifyOTPView,
    ResetPasswordView,
    FirebaseAuthView
)

urlpatterns = [
    path('register/', RegisterView.as_view(), name='register'),
    path('login/', LoginView.as_view(), name='login'),
    path('logout/', LogoutView.as_view(), name='logout'),
    path('google/', GoogleAuthView.as_view(), name='google_auth'),
    path('verify-email/send/', SendVerificationEmailView.as_view(), name='send_verification'),
    path('token/verify/', TokenVerifyView.as_view(), name='verify_token'),
    
    # Your existing endpoints
    path('send-otp/', SendOTPView.as_view(), name='send_otp'),
    path('verify-otp/', VerifyOTPView.as_view(), name='verify_otp'),
    path('reset-password/', ResetPasswordView.as_view(), name='reset_password'),
    path('firebase-login/', FirebaseAuthView.as_view(), name='firebase_login'),
    
    # JWT endpoints (for Swagger)
    path('token/refresh/', 'rest_framework_simplejwt.views.TokenRefreshView', name='token_refresh'),
]