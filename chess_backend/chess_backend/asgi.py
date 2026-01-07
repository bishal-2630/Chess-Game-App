import os
from django.core.asgi import get_asgi_application
from channels.routing import ProtocolTypeRouter, URLRouter
from channels.auth import AuthMiddlewareStack
import chess_backend.routing

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'chess_backend.settings')

application = ProtocolTypeRouter({
    "http": get_asgi_application(),
    "websocket": AuthMiddlewareStack(
        URLRouter(
            chess_backend.routing.websocket_urlpatterns
        )
    ),
})
