"""
Vercel serverless function handler for Flutter application
"""
from django.http import HttpResponse

def handler(request):
    """Minimal Vercel handler"""
    try:
        return HttpResponse("Handler working! Path: " + str(request.path), content_type='text/html')
    except Exception as e:
        return HttpResponse(f"Error: {str(e)}", status=500)

# Vercel Python runtime looks for 'app' variable
app = handler
