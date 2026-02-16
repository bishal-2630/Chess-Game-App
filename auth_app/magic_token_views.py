from django.contrib.auth import login
from django.shortcuts import redirect
from django.utils import timezone
from django.http import JsonResponse, HttpResponse
from .models import MagicHandshake
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
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
    """
    token_str = request.GET.get('token')
    next_url = request.GET.get('next', '/')
    
    print(f"🪄 [VerifyMagicToken] Attempting verification for token: {token_str[:8]}...")
    
    if not token_str:
        return HttpResponse("No token provided", status=400)
        
    try:
        handshake = MagicHandshake.objects.get(token=token_str)
    except (MagicHandshake.DoesNotExist, ValueError):
        print(f"❌ [VerifyMagicToken] Invalid or missing token")
        return HttpResponse("Invalid token", status=404)
        
    if not handshake.is_valid():
        print(f"❌ [VerifyMagicToken] Token expired or used: {handshake.token}")
        return HttpResponse("Token expired or already used", status=400)
        
    # LOG THE USER IN
    user = handshake.user
    login(request, user)
    
    # Save session explicitly to be sure
    request.session.save()
    session_key = request.session.session_key
    
    print(f"✅ [VerifyMagicToken] User {user.username} logged in. Session: {session_key[:8]}...")
    
    handshake.is_used = True
    handshake.save()
    
    # Add a success flag so Flutter Web knows to bootstrap
    if '?' in next_url:
        target = f"{next_url}&session_transfer=success"
    else:
        target = f"{next_url}?session_transfer=success"
        
    response = redirect(target)
    
    # Force the cookie with Lax for maximum reliability on same-site
    response.set_cookie(
        'sessionid', 
        session_key,
        max_age=60 * 60 * 24 * 7,
        secure=True, 
        httponly=False,
        samesite='Lax',
        path='/'
    )
    
    return response
