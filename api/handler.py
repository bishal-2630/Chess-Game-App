"""
Robust WSGI-to-Lambda bridge for Django on Vercel.
Uses the BaseHTTPRequestHandler pattern which is proven to work in health.py.
"""
import os
import sys
import json
import traceback
from io import BytesIO
from pathlib import Path
from http.server import BaseHTTPRequestHandler

# Add project root to sys.path
BASE_DIR = Path(__file__).resolve().parent.parent
if str(BASE_DIR) not in sys.path:
    sys.path.insert(0, str(BASE_DIR))

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'chess_backend.settings')

# Lazy load Django to catch startup errors
_application = None
_startup_error = None

def get_app():
    global _application, _startup_error
    if _application is not None:
        return _application
    if _startup_error is not None:
        return None
        
    try:
        import django
        django.setup()
        from django.core.wsgi import get_wsgi_application
        _application = get_wsgi_application()
        return _application
    except Exception:
        _startup_error = traceback.format_exc()
        return None

class handler(BaseHTTPRequestHandler):
    def do_ANY(self):
        app = get_app()
        if not app:
            self.send_response(500)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            error_resp = {
                "error": "Django Setup Failed",
                "traceback": _startup_error
            }
            self.wfile.write(json.dumps(error_resp).encode())
            return

        # Prepare WSGI environment
        path_info = self.path.split('?')[0]
        query_string = self.path.split('?')[1] if '?' in self.path else ''
        
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length) if content_length > 0 else b''

        environ = {
            'REQUEST_METHOD': self.command,
            'PATH_INFO': path_info,
            'QUERY_STRING': query_string,
            'SERVER_NAME': 'localhost',
            'SERVER_PORT': '80',
            'SERVER_PROTOCOL': 'HTTP/1.1',
            'wsgi.version': (1, 0),
            'wsgi.url_scheme': 'https',
            'wsgi.input': BytesIO(body),
            'wsgi.errors': sys.stderr,
            'wsgi.multithread': False,
            'wsgi.multiprocess': False,
            'wsgi.run_once': False,
        }

        # Add headers to environ
        for key, value in self.headers.items():
            key = 'HTTP_' + key.upper().replace('-', '_')
            if key in ('HTTP_CONTENT_TYPE', 'HTTP_CONTENT_LENGTH'):
                environ[key[5:]] = value
            else:
                environ[key] = value

        response_status = []
        response_headers = []

        def start_response(status, headers, exc_info=None):
            response_status.append(status)
            response_headers.append(headers)

        try:
            result = app(environ, start_response)
            
            # Send response back to Vercel
            status_code = int(response_status[0].split()[0])
            self.send_response(status_code)
            for header_name, header_value in response_headers[0]:
                self.send_header(header_name, header_value)
            self.end_headers()
            
            for chunk in result:
                self.wfile.write(chunk)
            
            if hasattr(result, 'close'):
                result.close()
                
        except Exception:
            self.send_response(500)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(traceback.format_exc().encode())

    def do_GET(self): self.do_ANY()
    def do_POST(self): self.do_ANY()
    def do_PUT(self): self.do_ANY()
    def do_DELETE(self): self.do_ANY()
    def do_PATCH(self): self.do_ANY()
    def do_HEAD(self): self.do_ANY()
    def do_OPTIONS(self): self.do_ANY()
