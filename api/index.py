"""
Vercel serverless function handler for Flutter application
"""
import os
import sys
from pathlib import Path
from django.http import HttpResponse

# Add project root to Python path
project_root = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(project_root))

# Set Django settings module
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'chess_backend.settings')

def handler(request):
    """Direct Vercel handler that serves Flutter app"""
    try:
        path = request.path.lstrip('/')
        
        if not path or path == '':
            # Serve hardcoded Flutter HTML
            html_content = '''<!DOCTYPE html>
<html>
<head>
  <base href="/">
  <meta charset="UTF-8">
  <meta content="IE=Edge" http-equiv="X-UA-Compatible">
  <meta name="description" content="A new Flutter project.">
  <meta name="mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black">
  <meta name="apple-mobile-web-app-title" content="chess_game">
  <link rel="apple-touch-icon" href="icons/Icon-192.png">
  <link rel="icon" type="image/png" href="favicon.png"/>
  <title>chess_game</title>
  <link rel="manifest" href="manifest.json">
</head>
<body>
  <script src="flutter_bootstrap.js" async></script>
</body>
</html>'''
            return HttpResponse(html_content, content_type='text/html')
        
        else:
            # Try to serve static files
            file_path = project_root / path
            if file_path.exists() and file_path.is_file():
                if file_path.suffix.lower() in ['.html', '.htm', '.css', '.js']:
                    with open(file_path, 'r', encoding='utf-8') as f:
                        content = f.read()
                else:
                    with open(file_path, 'rb') as f:
                        content = f.read()
                
                # Set content type
                if file_path.suffix.lower() == '.js':
                    content_type = 'application/javascript'
                elif file_path.suffix.lower() == '.css':
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

# Import the WSGI application from chess_backend
from chess_backend.wsgi import application

# Vercel Python runtime looks for 'app' variable
app = application
