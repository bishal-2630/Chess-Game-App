import os
import sys
from pathlib import Path

# Add the project directory to the Python path
BASE_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BASE_DIR))

# Set Django settings module
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'chess_backend.settings')

# Import Django WSGI application
import django
django.setup()

from django.core.wsgi import get_wsgi_application

# Create the WSGI application
application = get_wsgi_application()

# Vercel expects 'app' as the handler
app = application
