from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from rest_framework import status
from django.utils import timezone
from datetime import timedelta
from django.contrib.auth import login
from django.shortcuts import redirect
from .models import MagicHandshake
import uuid

class GenerateMagicTokenView(APIView):
    """
    Called by the Flutter App (authenticated via JWT).
    Generates a short-lived token to transfer the session to a browser.
    """
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

class VerifyMagicTokenView(APIView):
    """
    Called by the System Browser (Chrome/Safari).
    Verifies the token, sets the session cookie, and redirects user.
    """
    permission_classes = [] 

    def get(self, request):
        token_str = request.query_params.get('token')
        next_url = request.query_params.get('next', '/')
        
        if not token_str:
            return Response({"error": "No token provided"}, status=status.HTTP_400_BAD_REQUEST)
            
        try:
            handshake = MagicHandshake.objects.get(token=token_str)
        except (MagicHandshake.DoesNotExist, ValueError):
            return Response({"error": "Invalid token"}, status=status.HTTP_404_NOT_FOUND)
            
        if not handshake.is_valid():
            return Response({"error": "Token expired or already used"}, status=status.HTTP_400_BAD_REQUEST)
            
        # Log the user in for the current BROWSER session (sets the cookie)
        login(request, handshake.user)
        
        # Mark token as used
        handshake.is_used = True
        handshake.save()
        
        # Redirect to the target page (e.g., /play)
        return redirect(next_url)
