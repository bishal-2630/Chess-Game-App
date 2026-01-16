"""
Django views for serving the Flutter app
"""
from django.http import HttpResponse
from pathlib import Path

def serve_flutter_app(request):
    """Serve the Flutter app"""
    try:
        # Simple test first
        return HttpResponse("Django is working! Path: " + request.path, content_type='text/html')
        
    except Exception as e:
        return HttpResponse(f"Error: {str(e)}", status=500)
