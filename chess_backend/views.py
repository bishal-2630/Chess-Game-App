"""
Django views for serving the Flutter app
"""
from django.http import HttpResponse, HttpResponseNotFound
from django.conf import settings
from pathlib import Path
import mimetypes
import os

def serve_flutter_app(request):
    """Serve the main Flutter app"""
    try:
        # In Vercel, files are deployed to /var/task/ directly
        possible_paths = [
            Path('/var/task/index.html'),
            Path(settings.BASE_DIR) / 'index.html',
            Path('index.html'),
        ]
        
        index_path = None
        for path in possible_paths:
            if path.exists():
                index_path = path
                break
        
        if index_path:
            with open(index_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            response = HttpResponse(content, content_type='text/html')
            return response
        else:
            return HttpResponseNotFound("Flutter app not found")
            
    except Exception as e:
        return HttpResponse(f"Error: {str(e)}", status=500)

def serve_any_file(request, path):
    """Serve any file (catch-all for assets)"""
    try:
        # Try multiple possible locations
        possible_paths = [
            Path('/var/task') / path,
            Path(settings.BASE_DIR) / path,
            Path(path),
        ]
        
        file_path = None
        for p in possible_paths:
            if p.exists() and p.is_file():
                file_path = p
                break
        
        if file_path:
            # Determine content type
            content_type, _ = mimetypes.guess_type(str(file_path))
            if content_type is None:
                content_type = 'application/octet-stream'
            
            with open(file_path, 'rb') as f:
                content = f.read()
            
            response = HttpResponse(content, content_type=content_type)
            return response
        else:
            return HttpResponseNotFound(f"File not found: {path}")
            
    except Exception as e:
        return HttpResponse(f"Error serving file: {str(e)}", status=500)
