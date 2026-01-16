"""
Django views for serving the Flutter app
"""
from django.http import HttpResponse, HttpResponseNotFound
from django.conf import settings
from pathlib import Path
import mimetypes
import os

def serve_flutter_app(request):
    """Serve the main Flutter app or its assets"""
    try:
        # Get the requested path
        path = request.path.lstrip('/')
        
        # If no path, serve index.html
        if not path:
            possible_paths = [
                Path('/var/task/index.html'),
                Path(settings.BASE_DIR) / 'index.html',
                Path('index.html'),
            ]
            
            for p in possible_paths:
                if p.exists():
                    file_path = p
                    break
        else:
            # Serve assets and other files
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
            
            # Read file content
            if file_path.suffix == '.html':
                with open(file_path, 'r', encoding='utf-8') as f:
                    content = f.read()
            else:
                with open(file_path, 'rb') as f:
                    content = f.read()
            
            response = HttpResponse(content, content_type=content_type)
            return response
        else:
            return HttpResponseNotFound(f"File not found: {path}")
            
    except Exception as e:
        return HttpResponse(f"Error: {str(e)}", status=500)
