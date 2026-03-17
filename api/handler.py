import os
import sys
from pathlib import Path

# Add the project directory to the Python path
BASE_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BASE_DIR))

# Set Django settings module
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'chess_backend.settings')

_startup_error = None

try:
    import django
    django.setup()
    from django.core.wsgi import get_wsgi_application
    application = get_wsgi_application()
    app = application
except Exception as e:
    import traceback
    _startup_error = traceback.format_exc()

    # Serve a diagnostic WSGI app instead of crashing silently
    def app(environ, start_response):
        status = '500 Internal Server Error'
        headers = [('Content-Type', 'application/json')]
        start_response(status, headers)
        import json
        body = json.dumps({
            'error': 'Django startup failed',
            'detail': str(e),
            'traceback': _startup_error
        })
        return [body.encode('utf-8')]
