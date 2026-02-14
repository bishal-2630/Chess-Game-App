"""
Django views for serving Flutter app and assets
"""
from django.shortcuts import render
from django.http import HttpResponse
from django.conf import settings
from pathlib import Path
import os

def serve_flutter_app(request, path=''):
    """
    Serve the compiled Flutter web app (index.html) for SPA routes.
    Assets are served via Whitenoise/STATIC_URL, but this handles
    deep links like /play, /game/:id by returning the entry point.
    """
    path = path.lstrip('/')
    
    # Check if we should serve a static asset manually (fallback)
    # Primarily for assets that might not be under /static/ URL
    if path and '.' in Path(path).name:
        # Check STATIC_ROOT (staticfiles) first
        static_file = settings.STATIC_ROOT / path
        if static_file.exists():
            return _serve_file(static_file)
            
    # For all non-file routes (deep links), serve index.html
    # Try STATIC_ROOT/index.html first (collected static)
    index_path = settings.STATIC_ROOT / 'index.html'
    
    if index_path.exists():
        with open(index_path, 'r', encoding='utf-8') as f:
            return HttpResponse(f.read(), content_type='text/html')
            
    # Fallback to the public template if staticfiles build is missing
    # (This ensures we don't break if staticfiles creates an issue)
    return render(request, 'chess_web.html')

def _serve_file(file_path):
    """Helper to serve a file with correct content type"""
    suffix = file_path.suffix.lower()
    content_type = 'application/octet-stream'
    
    if suffix == '.js':
        content_type = 'application/javascript'
    elif suffix == '.css':
        content_type = 'text/css'
    elif suffix in ['.png', '.jpg', '.jpeg', '.gif', '.ico']:
        content_type = 'image/*'
    elif suffix in ['.html', '.htm']:
        content_type = 'text/html'
    elif suffix == '.json':
        content_type = 'application/json'
    elif suffix == '.map':
        content_type = 'application/json'
        
    try:
        with open(file_path, 'rb') as f:
            content = f.read()
        return HttpResponse(content, content_type=content_type)
    except Exception as e:
        return HttpResponse(f"Error serving file: {str(e)}", status=500)
