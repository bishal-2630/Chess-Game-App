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
        # Debug: Print base directory and check paths
        base_dir = Path(settings.BASE_DIR)
        index_path = base_dir / 'public' / 'index.html'
        
        # Debug info (will appear in logs)
        print(f"Base directory: {base_dir}")
        print(f"Index path: {index_path}")
        print(f"Index path exists: {index_path.exists()}")
        
        # List contents of public directory for debugging
        public_dir = base_dir / 'public'
        if public_dir.exists():
            print(f"Public directory contents: {list(public_dir.iterdir())}")
        else:
            print(f"Public directory does not exist at: {public_dir}")
        
        if index_path.exists():
            with open(index_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            # Set the correct content type
            response = HttpResponse(content, content_type='text/html')
            return response
        else:
            error_msg = f"Flutter app not found. Looking for: {index_path}"
            print(error_msg)
            return HttpResponse(error_msg, status=404)
            
    except Exception as e:
        error_msg = f"Error serving Flutter app: {str(e)}"
        print(error_msg)
        return HttpResponse(error_msg, status=500)
