class DisableCSRFOnSpecificAPIsMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        # Check if the request path is one of the bypass endpoints
        if request.path.startswith('/api/auth/final-bypass/') or \
           request.path.startswith('/api/auth/emergency/') or \
           request.path.startswith('/api/auth/bypass/'):
            # This is the correct way to tell Django to skip CSRF checks
            request._dont_enforce_csrf_checks = True
            request.csrf_processing_done = True
            print(f"🚫 CSRF Disabled for path: {request.path}")

        response = self.get_response(request)
        return response
