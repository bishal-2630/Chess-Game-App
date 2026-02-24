import os
import django
from django.core.asgi import get_asgi_application
from channels.routing import ProtocolTypeRouter, URLRouter

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'chess_backend.settings')
django.setup()

# Import from existing middleware file
from auth_app.middleware import JWTAuthMiddleware
import chess_backend.routing

application = ProtocolTypeRouter({
    "http": get_asgi_application(),
    "websocket": JWTAuthMiddleware(
        URLRouter(
            chess_backend.routing.websocket_urlpatterns
        )
    ),
})