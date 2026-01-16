"""
Django views for serving the Flutter app
"""
from django.http import HttpResponse
from pathlib import Path

def serve_flutter_app(request):
    """Serve the Flutter app"""
    try:
        # Simple approach: serve index.html for root, try to serve files for other paths
        path = request.path.lstrip('/')
        
        if not path or path == '':
            # Serve index.html for root
            index_path = Path('index.html')
            if index_path.exists():
                with open(index_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                return HttpResponse(content, content_type='text/html')
            else:
                return HttpResponse("index.html not found", status=404)
        else:
            # Try to serve the requested file
            file_path = Path(path)
            if file_path.exists() and file_path.is_file():
                # Read as binary for non-HTML files
                if file_path.suffix.lower() in ['.html', '.htm', '.css', '.js']:
                    with open(file_path, 'r', encoding='utf-8') as f:
                        content = f.read()
                else:
                    with open(file_path, 'rb') as f:
                        content = f.read()
                
                # Basic content type detection
                if file_path.suffix.lower() in ['.js']:
                    content_type = 'application/javascript'
                elif file_path.suffix.lower() in ['.css']:
                    content_type = 'text/css'
                elif file_path.suffix.lower() in ['.png', '.jpg', '.jpeg', '.gif', '.ico']:
                    content_type = 'image/*'
                elif file_path.suffix.lower() in ['.html', '.htm']:
                    content_type = 'text/html'
                else:
                    content_type = 'application/octet-stream'
                
                return HttpResponse(content, content_type=content_type)
            else:
                return HttpResponse(f"File not found: {path}", status=404)
                
    except Exception as e:
        return HttpResponse(f"Error: {str(e)}", status=500)
