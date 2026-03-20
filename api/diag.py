"""
Diagnostic script using BaseHTTPRequestHandler style (proven to work in health.py)
"""
import json
import os
import sys
import traceback
from http.server import BaseHTTPRequestHandler
from pathlib import Path

class handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        
        info = {
            "status": "diagnostic_active",
            "python_version": sys.version,
            "cwd": os.getcwd(),
            "env": {k: v for k, v in os.environ.items() if "KEY" not in k and "SECRET" not in k and "TOKEN" not in k},
            "django_load": "Not attempted"
        }
        
        try:
            # Add BASE_DIR to path
            BASE_DIR = Path(__file__).resolve().parent.parent
            if str(BASE_DIR) not in sys.path:
                sys.path.insert(0, str(BASE_DIR))
            
            os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'chess_backend.settings')
            
            import django
            django.setup()
            info["django_load"] = "Success"
            info["django_version"] = django.get_version()
            
            from django.core.wsgi import get_wsgi_application
            application = get_wsgi_application()
            info["wsgi_app_init"] = "Success"
            
        except Exception as e:
            info["django_load"] = "Failed"
            info["error_detail"] = str(e)
            info["traceback"] = traceback.format_exc()
            
        self.wfile.write(json.dumps(info, indent=2).encode())
        return
