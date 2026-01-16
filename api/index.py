"""
Vercel serverless function handler for Flutter application
"""
from django.http import HttpResponse

def handler(environ):
    """Standard Vercel handler with environ parameter"""
    try:
        # Get path from query string or path info
        path_info = environ.get('PATH_INFO', '').lstrip('/')
        
        return HttpResponse("Handler working! Path: " + path_info, content_type='text/html')
    except Exception as e:
        return HttpResponse(f"Error: {str(e)}", status=500)

# Vercel Python runtime looks for 'app' variable
app = handler
