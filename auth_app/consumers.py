import json
from channels.generic.websocket import AsyncWebsocketConsumer
from channels.db import database_sync_to_async

class SignalingConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        self.room_id = self.scope['url_route']['kwargs']['room_id']
        self.room_group_name = f'call_{self.room_id}'
        self.user = self.scope["user"]
        
        print(f"📡 Connection attempt to room: {self.room_id}")

        # Join room group
        await self.channel_layer.group_add(
            self.room_group_name,
            self.channel_name
        )

        # Update user online status
        await self.update_user_status(True, self.room_id)

        await self.accept()
        print(f"✅ Connection accepted for room: {self.room_id}")

    async def disconnect(self, close_code):
        # Leave room group
        await self.channel_layer.group_discard(
            self.room_group_name,
            self.channel_name
        )
        
        # Update user offline status
        await self.update_user_status(False, None)

    # Receive message from WebSocket
    async def receive(self, text_data):
        data = json.loads(text_data)
        
        # Handle different message types
        message_type = data.get('type', 'signaling')
        
        if message_type == 'signaling':
            # Forward signaling message to room group
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

    @database_sync_to_async
    def update_user_status(self, is_online, room_id):
        if self.user.is_authenticated:
            from django.contrib.auth import get_user_model
            User = get_user_model()
            user = User.objects.get(id=self.user.id)
            user.is_online = is_online
            user.current_room = room_id if is_online else None
            user.save()

class UserNotificationConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        if self.scope["user"].is_authenticated:
            self.user_id = self.scope["user"].id
            self.user_group_name = f'user_{self.user_id}'
            
            # Join user-specific group for notifications
            await self.channel_layer.group_add(
                self.user_group_name,
                self.channel_name
            )
            
            await self.accept()
            print(f"✅ User notification connected: {self.user_id}")
        else:
            await self.close()

    async def disconnect(self, close_code):
        if hasattr(self, 'user_group_name'):
            await self.channel_layer.group_discard(
                self.user_group_name,
                self.channel_name
            )

    async def game_invitation(self, event):
        """Handle incoming game invitation"""
        await self.send(text_data=json.dumps({
            'type': 'game_invitation',
            'data': event['invitation']
        }))

    async def invitation_response(self, event):
        """Handle invitation response (accept/decline)"""
        await self.send(text_data=json.dumps({
            'type': 'invitation_response',
            'data': {
                'invitation': event['invitation'],
                'action': event['action']
            }
        }))

    async def invitation_cancelled(self, event):
        """Handle invitation cancellation"""
        await self.send(text_data=json.dumps({
            'type': 'invitation_cancelled',
            'data': event['invitation']
        }))
