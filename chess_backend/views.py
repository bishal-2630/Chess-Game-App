"""
Django views for serving the Flutter app
"""
from django.http import HttpResponse
from django.conf import settings
from pathlib import Path
import os

def serve_flutter_app(request):
    """Serve the Flutter app index.html file"""
    try:
        # In Vercel, files are deployed to /var/task/ directly
        # Try multiple possible locations
        possible_paths = [
            Path('/var/task/index.html'),  # Vercel deployment directory
            Path(settings.BASE_DIR) / 'public' / 'index.html',  # Local development
            Path(settings.BASE_DIR) / 'index.html',  # Alternative
        ]
        
        index_path = None
        for path in possible_paths:
            if path.exists():
                index_path = path
                break
        
        if index_path:
            with open(index_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            # Set the correct content type
            response = HttpResponse(content, content_type='text/html')
            return response
        else:
            error_msg = f"Flutter app not found. Tried paths: {possible_paths}"
            print(error_msg)
            return HttpResponse(error_msg, status=404)
            
    except Exception as e:
        error_msg = f"Error serving Flutter app: {str(e)}"
        print(error_msg)
        return HttpResponse(error_msg, status=500)
