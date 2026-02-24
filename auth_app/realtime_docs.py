from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from drf_yasg.utils import swagger_auto_schema
from drf_yasg import openapi

class MQTTDocumentationView(APIView):
    """
    MQTT Documentation for Real-time Notifications.
    This is a reference only view and does not provide an HTTP interface.
    """
    @swagger_auto_schema(
        operation_description="""
        ### MQTT Service Overview
        The application uses MQTT for background notifications and high-priority signaling (e.g., incoming calls).

        **Broker**: `broker.emqx.io` (Port 1883)
        **Protocol**: MQTT v3.1.1

        ### Topics
        - `chess/user/{username}/notifications`: Primary topic for user-specific notifications.

        ### Message Format (JSON)
        ```json
        {
            "type": "string",
            "payload": { ... }
        }
        ```

        ### Notification Types
        | Type | Description | Payload |
        |---|---|---|
        | `game_invitation` | New match request | `GameInvitationSerializer` |
        | `invitation_response` | User accepted/declined | `{"invitation": ..., "action": "accept/decline"}` |
        | `invitation_cancelled` | Sender revoked invite | `GameInvitationSerializer` |
        | `call_invitation` | Incoming WebRTC call | `{"caller": "name", "room_id": "id", "caller_picture": "url"}` |
        | `call_declined` | Call was rejected | `{"decliner": "name", "room_id": "id"}` |
        | `call_cancelled` | Caller ended attempt | `{"caller": "name", "room_id": "id"}` |
        """,
        responses={200: openapi.Response("Documentation reference only")}
    )
    def get(self, request):
        return Response({"message": "Refer to Swagger documentation for MQTT details."}, status=status.HTTP_200_OK)

class WebSocketDocumentationView(APIView):
    """
    WebSocket Documentation for In-Game Signaling.
    This is a reference only view and does not provide an HTTP interface.
    """
    @swagger_auto_schema(
        operation_description="""
        ### WebSocket Service Overview
        WebSockets are used for low-latency in-game signaling and live UI updates.

        **Base URL**: `ws://{host}/ws/` (or `wss://` for HTTPS)

        ### Endpoints
        - `/ws/notifications/`: Live notification stream (Alternative to MQTT when app is foregrounded).
        - `/ws/signaling/{room_id}/`: WebRTC signaling for active calls.

        ### Signaling Protocol (/ws/signaling/)
        All participants in a `room_id` receive messages sent to this socket.

        **Client -> Server**:
        ```json
        {
            "type": "offer/answer/candidate",
            "sdp/candidate": "...",
            "target": "username"
        }
        ```

        **Server -> Client (Signaling)**:
        Returns the same message to all other participants in the room.

        ### Notification Socket Events (/ws/notifications/)
        - `game_invitation`
        - `invitation_response`
        - `invitation_cancelled`
        - `call_invitation`
        """,
        responses={200: openapi.Response("Documentation reference only")}
    )
    def get(self, request):
        return Response({"message": "Refer to Swagger documentation for WebSocket details."}, status=status.HTTP_200_OK)
