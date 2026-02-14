from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework.permissions import IsAuthenticated
from django.contrib.sessions.models import Session
from django.utils import timezone
from datetime import timedelta
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
            
            # Create a new session
            session_key = secrets.token_urlsafe(32)
            
            # Set session expiration (7 days to match JWT refresh token)
            expiration = timezone.now() + timedelta(days=7)
            
            # Create session data
            session_data = {
                'user_id': user.id,
                'username': user.username,
                'email': user.email,
                'authenticated': True,
                'created_at': timezone.now().isoformat(),
            }
            
            # Store session in Django's session framework
            request.session.update(session_data)
            request.session.set_expiry(expiration)
            
            # Get the session key
            actual_session_key = request.session.session_key
            if not actual_session_key:
                request.session.create()
                actual_session_key = request.session.session_key
            
            response_data = {
                'success': True,
                'session_key': actual_session_key,
                'expires_at': expiration.isoformat(),
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
