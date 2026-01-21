from django.urls import path
from django.http import JsonResponse
import time
from .swagger_views import (
    RegisterView, LoginView, LogoutView,
    SendOTPView, VerifyOTPView, ResetPasswordView,VerifyEmailTokenView,
    SendVerificationEmailView,
    TokenVerifyView,
    GuestRegisterView, HealthCheckView
)
from .views import ConnectivityCheckView, TestEmailView
from .google_auth_views import GoogleLoginView
from .game_views import (
    OnlineUsersView, AllUsersView, UpdateOnlineStatusView,
    SendInvitationView, MyInvitationsView, RespondToInvitationView,
    cancel_invitation, SendCallSignalView
)

def direct_health(request):
    return JsonResponse({"status": "v3_direct_ok", "phase": "csrf_final_decisive"})

def rollout_proof(request):
    return JsonResponse({"rollout": "FORCE_SYNC_SUCCESS", "ts": time.time()})

urlpatterns = [
    path('', direct_health),
    # Prototyping rollout proof
    path('health-v5/', rollout_proof),
    
    # Direct Health (No dependency on swagger_views)
    path('health-direct/', direct_health),
    
    # Core Authentication
    path('register/', RegisterView.as_view(), name='register'),
    path('login/', LoginView.as_view(), name='login'),
    path('logout/', LogoutView.as_view(), name='logout'),
    
    # Debug/Networking
    path('debug/network/', ConnectivityCheckView.as_view(), name='network_check'),
    path('debug/email-test/', TestEmailView.as_view(), name='email_test'),
    
    # Password Management
    path('send-otp/', SendOTPView.as_view(), name='send_otp'),
    path('verify-otp/', VerifyOTPView.as_view(), name='verify_otp'),
    path('reset-password/', ResetPasswordView.as_view(), name='reset_password'),
    
    
    # Social & Guest Auth
    # path('firebase-login/', FirebaseAuthView.as_view(), name='firebase_login'),
    path('google-login/', GoogleLoginView.as_view(), name='google_login'),
    path('guest/', GuestRegisterView.as_view(), name='guest_register'),
    
    # Email Verification
    path('verify-email/send/', SendVerificationEmailView.as_view(), name='send_verification'),
    path('verify-email/', VerifyEmailTokenView.as_view(), name='verify_email'),
    
    # Token Operations
    path('token/verify/', TokenVerifyView.as_view(), name='verify_token'),
    
    # Health Check
    path('health-new/', HealthCheckView.as_view(), name='health_check'),
    
    # Game & User Management
    path('users/online/', OnlineUsersView.as_view(), name='online_users'),
    path('users/all/', AllUsersView.as_view(), name='all_users'),
    path('users/status/', UpdateOnlineStatusView.as_view(), name='update_status'),
    path('invitations/send/', SendInvitationView.as_view(), name='send_invitation'),
    path('invitations/my/', MyInvitationsView.as_view(), name='my_invitations'),
    path('invitations/<int:invitation_id>/respond/', RespondToInvitationView.as_view(), name='respond_invitation'),
    path('invitations/<int:invitation_id>/cancel/', cancel_invitation, name='cancel_invitation'),
    path('call/send/', SendCallSignalView.as_view(), name='send_call_signal'),
]