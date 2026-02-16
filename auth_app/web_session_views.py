from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework.permissions import IsAuthenticated
from rest_framework.authentication import SessionAuthentication
from django.utils import timezone
from datetime import timedelta
from django.contrib.auth import login

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
            user = request.user
            login(request, user)
            
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
                samesite='None',
            )
            return response
        except Exception as e:
            return Response(
                {'success': False, 'error': str(e)},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )

    def get(self, request):
        """
        Bootstrap endpoint for Flutter Web.
        If the browser has a valid session cookie, return JWT tokens.
        """
        if not request.user.is_authenticated:
            return Response(
                {"success": False, "error": "Not authenticated via session"},
                status=status.HTTP_401_UNAUTHORIZED
            )

        from rest_framework_simplejwt.tokens import RefreshToken
        refresh = RefreshToken.for_user(request.user)
        
        return Response({
            "success": True,
            "access": str(refresh.access_token),
            "refresh": str(refresh),
            "user": {
                "id": request.user.id,
                "username": request.user.username,
                "email": request.user.email,
            }
        }, status=status.HTTP_200_OK)
