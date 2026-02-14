from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework.permissions import IsAuthenticated
from django.contrib.sessions.models import Session
from django.utils import timezone
from datetime import timedelta
from django.contrib.auth import login
import secrets


class WebSessionView(APIView):
    """
    Generate a session cookie from a valid JWT token.
    This allows Flutter app to inject cookies into WebView for seamless web authentication.
    """
    authentication_classes = [JWTAuthentication]
    permission_classes = [IsAuthenticated]

    def post(self, request):
        """
        Accept JWT token, return session cookie.
        
        Request:
            Authorization: Bearer <jwt_token>
        
        Response:
            {
                "success": true,
                "session_key": "abc123...",
                "expires_at": "2024-02-20T12:00:00Z"
            }
        """
        try:
            user = request.user
            
            # Use Django's login system to associate the user with the session correctly
            # This sets _auth_user_id and other required keys for AuthenticationMiddleware
            login(request, user)
            
            # Set session expiration (7 days to match JWT refresh token)
            request.session.set_expiry(60 * 60 * 24 * 7)
            
            # Get the session key
            actual_session_key = request.session.session_key
            if not actual_session_key:
                request.session.create()
                actual_session_key = request.session.session_key
            
            response_data = {
                'success': True,
                'session_key': actual_session_key,
                'expires_at': (timezone.now() + timedelta(days=7)).isoformat(),
                'user': {
                    'id': user.id,
                    'username': user.username,
                    'email': user.email,
                }
            }
            
            # Create response with session cookie
            response = Response(response_data, status=status.HTTP_200_OK)
            
            # Set the session cookie in the response
            response.set_cookie(
                key='sessionid',
                value=actual_session_key,
                max_age=60 * 60 * 24 * 7,  # 7 days
                expires=expiration,
                path='/',
                domain=None,  # Will use current domain
                secure=True,  # HTTPS only
                httponly=False,  # Allow JavaScript access for WebView
                samesite='None',  # Allow cross-origin for WebView
            )
            
            return response
            
        except Exception as e:
            return Response(
                {
                    'success': False,
                    'error': f'Failed to create web session: {str(e)}'
                },
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )
