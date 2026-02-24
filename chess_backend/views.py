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
    Prevents shadowing API and Admin paths.
    """
    # 1. Protection: If this path starts with api/ or admin/, and we reached here,
    # it means the URL didn't match any pattern. Return a 404 instead of index.html
    # to prevent Flutter from trying to "render" an API error.
    clean_path = path.lstrip('/')
    if clean_path.startswith(('api/', 'admin/', 'swagger/')):
        return HttpResponse(f"Not Found: {path}", status=404)

    # 2. Check for Static Assets
    # If the path has an extension, it's likely a file.
    if '.' in os.path.basename(clean_path):
        # Look in STATIC_ROOT (Collected static)
        static_file = settings.STATIC_ROOT / clean_path
        if static_file.exists():
            return _serve_file(static_file)
        
        # Look in STATICFILES_DIRS (Development build)
        for static_dir in settings.STATICFILES_DIRS:
            static_file = Path(static_dir) / clean_path
            if static_file.exists():
                return _serve_file(static_file)

        # If it's a missing file request, don't serve index.html
        return HttpResponse(f"Asset not found: {path}", status=404)

    # 3. SPA Fallback: Serve index.html for all deep links
    # Try STATIC_ROOT/index.html first
    index_path = settings.STATIC_ROOT / 'index.html'
    if not index_path.exists():
        for static_dir in settings.STATICFILES_DIRS:
            p = Path(static_dir) / 'index.html'
            if p.exists():
                index_path = p
                break

    if index_path.exists():
        with open(index_path, 'r', encoding='utf-8') as f:
            return HttpResponse(f.read(), content_type='text/html')
            
    # Final fallback
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

def serve_assetlinks(request):
    """Serve the .well-known/assetlinks.json file for App Links verification"""
    file_path = settings.BASE_DIR / '.well-known' / 'assetlinks.json'
    if file_path.exists():
        with open(file_path, 'r') as f:
            return HttpResponse(f.read(), content_type='application/json')
    return HttpResponse('File not found', status=404)
