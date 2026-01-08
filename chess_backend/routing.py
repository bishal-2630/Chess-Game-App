from django.urls import re_path
from auth_app import consumers

websocket_urlpatterns = [
    re_path(r'ws/call/(?P<room_id>\w+)/$', consumers.SignalingConsumer.as_asgi()),
]
