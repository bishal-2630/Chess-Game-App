import json
from channels.generic.websocket import AsyncWebsocketConsumer

class SignalingConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        self.room_id = self.scope['url_route']['kwargs']['room_id']
        self.room_group_name = f'call_{self.room_id}'
        
        print(f"📡 Connection attempt to room: {self.room_id}")

        # Join room group
        await self.channel_layer.group_add(
            self.room_group_name,
            self.channel_name
        )

        await self.accept()
        print(f"✅ Connection accepted for room: {self.room_id}")

    async def disconnect(self, close_code):
        # Leave room group
        await self.channel_layer.group_discard(
            self.room_group_name,
            self.channel_name
        )

    # Receive message from WebSocket
    async def receive(self, text_data):
        data = json.loads(text_data)
        
        # Forward message to room group
        await self.channel_layer.group_send(
            self.room_group_name,
            {
                'type': 'signaling_message',
                'message': data,
                'sender_channel_name': self.channel_name
            }
        )

    # Receive message from room group
    async def signaling_message(self, event):
        message = event['message']
        sender_channel_name = event.get('sender_channel_name')

        # Do not send back to sender
        if self.channel_name != sender_channel_name:
            await self.send(text_data=json.dumps(message))
