import os
import django
from django.core.asgi import get_asgi_application
from channels.routing import ProtocolTypeRouter, URLRouter
from channels.auth import AuthMiddlewareStack


os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'chess_backend.settings')
django.setup()


import chess_backend.routing

application = ProtocolTypeRouter({
    "http": get_asgi_application(),
    "websocket": AuthMiddlewareStack(
        URLRouter(
            chess_backend.routing.websocket_urlpatterns
        )
    ),
})
