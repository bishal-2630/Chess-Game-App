class DisableCSRFOnSpecificAPIsMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        # Check if the request path is one of the bypass endpoints
        path = request.path
        if 'final-bypass' in path or 'emergency' in path or 'bypass' in path:
            # Re-verify and force disable
            request._dont_enforce_csrf_checks = True
            request.csrf_processing_done = True
            print(f"🚫 CSRF FORCE DISABLED for path: {path}")

        response = self.get_response(request)
        return response
