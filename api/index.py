from django.http import HttpResponse

def handler(environ, start_response=None):
    if start_response:
        status = '200 OK'
        headers = [('Content-Type', 'text/html')]
        start_response(status, headers)
        return [b"Working: Django environment might be available"]
    return HttpResponse("Working: Simple Handler", content_type='text/html')

app = handler
