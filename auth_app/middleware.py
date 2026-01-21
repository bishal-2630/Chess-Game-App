from django.utils.deprecation import MiddlewareMixin
from django.conf import settings
from channels.db import database_sync_to_async
from django.contrib.auth import get_user_model
from django.contrib.auth.models import AnonymousUser
from rest_framework_simplejwt.tokens import AccessToken
from rest_framework_simplejwt.exceptions import InvalidToken, TokenError
from urllib.parse import parse_qs


class DisableCSRFOnSpecificAPIsMiddleware(MiddlewareMixin):
    def process_request(self, request):
        # Check if the request path contains any bypass endpoints
        path = request.path
        bypass_paths = [
            'final-bypass',
            'emergency',
            'bypass',
            'google-login',  
            'firebase-login',
            'api/auth/google-login'  
        ]
        
        for bypass_path in bypass_paths:
            if bypass_path in path:
                # Force disable CSRF checks
                request._dont_enforce_csrf_checks = True
                print(f"🚫 CSRF DISABLED (MW) - Path: {path} - ID: {getattr(settings, 'DEPLOYMENT_ID', 'UNKNOWN')}")
                break
        
        return None

    def process_response(self, request, response):
        # Attach DEPLOYMENT_ID to every response for definitive identification
        try:
            dep_id = getattr(settings, 'DEPLOYMENT_ID', 'GHOST_OR_STALE')
            # Use multiple header formats to ensure at least one gets through
            response['X-Deployment-ID'] = dep_id
            response['X-App-Version'] = dep_id  # Alternative header name
            response['X-Custom-Deploy'] = dep_id  # Another alternative
            print(f"✅ HEADERS ADDED - ID: {dep_id}")
        except Exception as e:
            print(f"❌ HEADER ERROR: {str(e)}")
        return response

User = get_user_model()
@database_sync_to_async
def get_user(token_key):
    try:
        access_token = AccessToken(token_key)
        user_id = access_token['user_id']
        return User.objects.get(id=user_id)
    except (InvalidToken, TokenError, User.DoesNotExist):
        return AnonymousUser()
class JWTAuthMiddleware:
    def __init__(self, inner):
        self.inner = inner
    async def __call__(self, scope, receive, send):
        token = None
        headers = dict(scope['headers'])
        if b'authorization' in headers:
            try:
                auth_header = headers[b'authorization'].decode()
                if auth_header.startswith('Bearer '):
                    token = auth_header.split(' ')[1]
            except:
                pass
        if not token:
            query_string = scope.get('query_string', b'').decode()
            query_params = parse_qs(query_string)
            if 'token' in query_params:
                token = query_params['token'][0]
        if token:
            scope['user'] = await get_user(token)
        else:
            scope['user'] = AnonymousUser()
        return await self.inner(scope, receive, send)