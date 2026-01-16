def handler(environ):
    return HttpResponse("Working: " + str(environ.get('PATH_INFO', '/')), content_type='text/html')

app = handler
