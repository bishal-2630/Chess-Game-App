from django.urls import path
from .views import (
    SendOTPView,
    VerifyOTPView,
    ResetPasswordView,
    FirebaseAuthView
)

urlpatterns = [
    path('send-otp/', SendOTPView.as_view(), name='send_otp'),
    path('verify-otp/', VerifyOTPView.as_view(), name='verify_otp'),
    path('reset-password/', ResetPasswordView.as_view(), name='reset_password'),
    path('firebase-login/', FirebaseAuthView.as_view(), name='firebase_login'),
]