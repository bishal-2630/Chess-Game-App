from django.utils.deprecation import MiddlewareMixin
from django.conf import settings

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