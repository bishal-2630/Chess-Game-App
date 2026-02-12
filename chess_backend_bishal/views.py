"""
Django views for serving Flutter app
"""
from django.http import HttpResponse
from pathlib import Path

def serve_flutter_app(request):
    """Serve the Flutter app"""
    path = request.path.lstrip('/')
    
    # Serve assets (JS, CSS, images)
    if path and path != '':
        file_path = Path(path)
        if file_path.exists() and file_path.is_file():
            # Read file based on type
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
            return HttpResponse(f"Asset not found: {path}", status=404)
    
    # Serve main HTML for root path
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
