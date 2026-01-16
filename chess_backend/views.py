"""
Django views for serving the Flutter app
"""
from django.http import HttpResponse, HttpResponseNotFound
from django.conf import settings
from pathlib import Path
import os
import mimetypes

def serve_flutter_app(request):
    """Serve the Flutter app index.html file"""
    try:
        # In Vercel, files are deployed to /var/task/ directly
        # Try multiple possible locations
        possible_paths = [
            Path('/var/task/index.html'),  # Vercel deployment directory
            Path(settings.BASE_DIR) / 'index.html',  # Local development
            Path('index.html'),  # Current directory
        ]
        
        index_path = None
        for path in possible_paths:
            if path.exists():
                index_path = path
                break
        
        if index_path:
            with open(index_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            # Set the correct base href for Vercel deployment
            content = content.replace('<base href="/">', '<base href="/">')
            
            response = HttpResponse(content, content_type='text/html')
            return response
        else:
            error_msg = f"Flutter app not found. Tried paths: {possible_paths}"
            return HttpResponse(error_msg, status=404)
            
    except Exception as e:
        error_msg = f"Error serving Flutter app: {str(e)}"
        return HttpResponse(error_msg, status=500)

def serve_flutter_assets(request, path):
    """Serve Flutter static assets (JS, CSS, images, etc.)"""
    try:
        # Try multiple possible locations for assets
        possible_paths = [
            Path('/var/task') / path,  # Vercel deployment directory
            Path(settings.BASE_DIR) / path,  # Local development
            Path(path),  # Current directory
        ]
        
        asset_path = None
        for p in possible_paths:
            if p.exists() and p.is_file():
                asset_path = p
                break
        
        if asset_path:
            # Determine content type
            content_type, _ = mimetypes.guess_type(str(asset_path))
            if content_type is None:
                content_type = 'application/octet-stream'
            
            with open(asset_path, 'rb') as f:
                content = f.read()
            
            response = HttpResponse(content, content_type=content_type)
            return response
        else:
            return HttpResponseNotFound(f"Asset not found: {path}")
            
    except Exception as e:
        return HttpResponse(f"Error serving asset: {str(e)}", status=500)
