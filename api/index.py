"""
Vercel serverless function handler for Django application
"""
import os
import sys
from pathlib import Path
from django.http import HttpResponse

# Add the project root to Python path
project_root = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(project_root))

# Set Django settings module
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'chess_backend.settings')

def handler(request):
    """Simple Vercel handler that bypasses Django URLs"""
    return HttpResponse("Vercel handler is working! Request path: " + request.path, content_type='text/html')

# Import the WSGI application from chess_backend
from chess_backend.wsgi import application

# Vercel Python runtime looks for 'app' variable
app = application
