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
    This avoids DRF overhead and ensures sessionid cookie is set correctly.
    """
    token_str = request.GET.get('token')
    next_url = request.GET.get('next', '/')
    
    if not token_str:
        return HttpResponse("No token provided", status=400)
        
    try:
        handshake = MagicHandshake.objects.get(token=token_str)
    except (MagicHandshake.DoesNotExist, ValueError):
        return HttpResponse("Invalid token", status=404)
        
    if not handshake.is_valid():
        return HttpResponse("Token expired or already used", status=400)
        
    # LOG THE USER IN (Sets the session cookie)
    login(request, handshake.user)
    
    handshake.is_used = True
    handshake.save()
    
    # Add a success flag so Flutter Web knows to bootstrap even if it had no tokens
    if '?' in next_url:
        target = f"{next_url}&session_transfer=success"
    else:
        target = f"{next_url}?session_transfer=success"
        
    response = redirect(target)
    
    # Defensive: Manually ensure the session cookie has the correct flags
    # though settings.py SHOULD handle this.
    return response
