from django.contrib.auth import login
from django.shortcuts import redirect
from django.utils import timezone
from django.http import JsonResponse, HttpResponse
from .models import MagicHandshake
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework_simplejwt.tokens import RefreshToken
from datetime import timedelta
import logging

logger = logging.getLogger(__name__)

class GenerateMagicTokenView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        # Invalidate old tokens for this user
        MagicHandshake.objects.filter(user=request.user, is_used=False).update(is_used=True)
        
        # Create new 60-second token
        handshake = MagicHandshake.objects.create(
            user=request.user,
            expires_at=timezone.now() + timedelta(seconds=60)
        )
        
        return Response({
            "handshake_token": str(handshake.token),
            "expires_at": handshake.expires_at
        })

def verify_magic_token(request):
    """
    Plain Django view to handle magic token verification.
    Redirects to the app with JWT tokens in the URL fragment.
    """
    token_str = request.GET.get('token')
    next_url = request.GET.get('next', '/')
    
    print(f"🪄 [VerifyMagicToken] Start for token: {token_str[:8]}...")
    
    if not token_str:
        return HttpResponse("No token provided", status=400)
        
    try:
        handshake = MagicHandshake.objects.get(token=token_str)
    except (MagicHandshake.DoesNotExist, ValueError):
        return HttpResponse("Invalid token", status=404)
        
    if not handshake.is_valid():
        return HttpResponse("Token expired or already used", status=400)
        
    user = handshake.user
    handshake.is_used = True
    handshake.save()
    
    # Generate JWT tokens for the bridge
    refresh = RefreshToken.for_user(user)
    access_token = str(refresh.access_token)
    refresh_token = str(refresh)
    
    print(f"✅ [VerifyMagicToken] Success for {user.username}. Redirecting with tokens.")

    # BRIDGE: Bundle tokens in the URL fragment (#)
    # This is more secure (not sent to server) and bypasses all cookie issues.
    fragment = f"access={access_token}&refresh={refresh_token}&session_transfer=success"
    
    # Ensure next_url doesn't already have a fragment
    # We redirect to a special path /web-bridge that the app DOES NOT intercept
    # to ensure Chrome stays in the browser and doesn't bounce back to the app.
    target = f"/web-bridge?next={next_url}#{fragment}"
    
    response = redirect(target)
    
    # Still set the session cookie as a fallback for pure web users
    login(request, user)
    return response
