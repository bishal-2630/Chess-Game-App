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
        # Path to the index.html file in public directory
        index_path = Path(settings.BASE_DIR) / 'public' / 'index.html'
        
        if index_path.exists():
            with open(index_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            # Set the correct content type
            response = HttpResponse(content, content_type='text/html')
            return response
        else:
            return HttpResponse("Flutter app not found", status=404)
            
    except Exception as e:
        return HttpResponse(f"Error serving Flutter app: {str(e)}", status=500)
