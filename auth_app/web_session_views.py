from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework.permissions import IsAuthenticated
from rest_framework.authentication import SessionAuthentication
from django.utils import timezone
from datetime import timedelta
from django.contrib.auth import login
from django.middleware.csrf import get_token

class WebSessionView(APIView):
    """
    Generate a session cookie from a valid JWT token OR bootstrap JWT from session.
    """
    authentication_classes = [JWTAuthentication, SessionAuthentication]
    permission_classes = [IsAuthenticated]

    def post(self, request):
        """
        Accept JWT token, return session cookie.
        """
        try:
            print(f"🍪 [WebSessionView] POST called by {request.user.username}")
            user = request.user
            login(request, user)
            
            # CRITICAL: Ensure CSRF token is generated for the session
            csrf_token = get_token(request)
            print(f"🛡️ [WebSessionView] CSRF Token generated: {csrf_token[:8] if csrf_token else 'NONE'}")
            
            expires_delta = timedelta(days=7)
            request.session.set_expiry(60 * 60 * 24 * 7)
            
            actual_session_key = request.session.session_key
            if not actual_session_key:
                request.session.create()
                actual_session_key = request.session.session_key
            
            expiration = timezone.now() + expires_delta
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
            
            response = Response(response_data, status=status.HTTP_200_OK)
            response.set_cookie(
                key='sessionid',
                value=actual_session_key,
                max_age=60 * 60 * 24 * 7,
                expires=expiration,
                path='/',
                domain=None,
                secure=True,
                httponly=False,
                samesite='Lax',
            )
            return response
        except Exception as e:
            print(f"❌ [WebSessionView] POST Error: {e}")
            return Response(
                {'success': False, 'error': str(e)},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )

    def get(self, request):
        """
        Bootstrap endpoint for Flutter Web.
        If the browser has a valid session cookie OR valid JWT, 
        return JWT tokens and ensure session cookie is set.
        """
        if not request.user.is_authenticated:
            print(f"🍪 [WebSessionView] GET Bootstrap: UNAUTHORIZED")
            return Response(
                {"success": False, "error": "Not authenticated"},
                status=status.HTTP_401_UNAUTHORIZED
            )

        user = request.user
        print(f"🍪 [WebSessionView] GET Bootstrap: SUCCESS for {user.username}")
        
        # Ensure session cookie is set/refreshed for the browser
        login(request, user)
        request.session.set_expiry(60 * 60 * 24 * 7)
        
        from rest_framework_simplejwt.tokens import RefreshToken
        refresh = RefreshToken.for_user(user)
        
        response_data = {
            "success": True,
            "access": str(refresh.access_token),
            "refresh": str(refresh),
            "user": {
                "id": user.id,
                "username": user.username,
                "email": user.email,
            }
        }
        
        response = Response(response_data, status=status.HTTP_200_OK)
        # Re-inject cookie as a safety measure
        expires_delta = timedelta(days=7)
        expiration = timezone.now() + expires_delta
        response.set_cookie(
            key='sessionid',
            value=request.session.session_key,
            max_age=60 * 60 * 24 * 7,
            expires=expiration,
            path='/',
            secure=True,
            httponly=False,
            samesite='Lax',
        )
        return response
