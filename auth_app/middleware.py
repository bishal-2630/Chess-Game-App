
from django.utils.deprecation import MiddlewareMixin

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
                print(f"🚫 CSRF DISABLED for path: {path}")
                break
        
        return None