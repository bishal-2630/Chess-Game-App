def handler(environ):
    """Standard Vercel handler with environ parameter"""
    try:
        path = environ.get('PATH_INFO', '').lstrip('/')
        
        # Test different paths
        if path == '/test-auth':
            return HttpResponse("Auth endpoint working! Path: " + path, content_type='text/html')
        elif path == '/test-db':
            try:
                from django.db import connection
                from django.contrib.auth import get_user_model
                User = get_user_model()
                count = User.objects.count()
                return HttpResponse(f"DB working! Found {count} users. Path: " + path, content_type='text/html')
            except Exception as e:
                return HttpResponse(f"DB error: {str(e)}", status=500)
        else:
            return HttpResponse("Handler working! Path: " + path, content_type='text/html')
    except Exception as e:
        return HttpResponse(f"Error: {str(e)}", status=500)

app = handler
