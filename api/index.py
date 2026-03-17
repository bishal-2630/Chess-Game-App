def handler(environ, start_response):
    status = '200 OK'
    headers = [('Content-Type', 'text/html')]
    start_response(status, headers)
    import sys
    return [f"WSGI Working. Python version: {sys.version}".encode('utf-8')]

app = handler
