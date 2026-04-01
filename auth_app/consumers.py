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

        # Send confirmation to the player who just connected
        opponent = await self.get_room_opponent()
        await self.send(text_data=json.dumps({
            'type': 'connected',
            'status': 'success',
            'room_id': self.room_id,
            'opponent': opponent
        }))

        # Notify others in the room that we've joined WITH our profile info
        await self.channel_layer.group_send(
            self.room_group_name,
            {
                'type': 'signaling_message',
                'message': {
                    'type': 'player_joined',
                    'opponent': {
                        'username': self.user.username,
                        'profile_picture': self.user.profile_picture if hasattr(self.user, 'profile_picture') and self.user.profile_picture else None
                    }
                },
                'sender_channel_name': self.channel_name
            }
        )
        
        # Notify globally via MQTT that this user is now in a room
        try:
            from .mqtt_utils import publish_global_mqtt_notification
            publish_global_mqtt_notification('user_status_update', {
                'username': self.user.username,
                'is_online': True,
                'current_room': self.room_id
            })
        except Exception as e:
            print(f"⚠️ MQTT Global Broadcast failed: {e}")

    async def disconnect(self, close_code):
        # Leave room group
        await self.channel_layer.group_discard(
            self.room_group_name,
            self.channel_name
        )
        
        # Update user offline status
        await self.update_user_status(False, None)
        
        # Notify globally via MQTT that this user has left the room
        try:
            from .mqtt_utils import publish_global_mqtt_notification
            publish_global_mqtt_notification('user_status_update', {
                'username': self.user.username,
                'is_online': True, # Likely still in app
                'current_room': None
            })
        except Exception as e:
            print(f"⚠️ MQTT Global Broadcast failed: {e}")

    # Receive message from WebSocket
    async def receive(self, text_data):
        try:
            data = json.loads(text_data)
            
            # Logging for specific signal types
            if data.get('type') == 'end_call':
                print(f"📞 End call signal received from {self.user} in room {self.room_id}")

            # Unconditionally forward all signaling messages to room group
            await self.channel_layer.group_send(
                self.room_group_name,
                {
                    'type': 'signaling_message',
                    'message': data,
                    'sender_channel_name': self.channel_name
                }
            )
        except Exception as e:
            print(f"❌ Error in SignalingConsumer.receive: {e}")

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

    @database_sync_to_async
    def get_room_opponent(self):
        from django.contrib.auth import get_user_model
        User = get_user_model()
        # Find another user who is currently in this room
        try:
            opponent = User.objects.filter(current_room=self.room_id).exclude(id=self.user.id).first()
            if opponent:
                return {
                    'username': opponent.username,
                    'profile_picture': opponent.profile_picture if opponent.profile_picture else None
                }
        except Exception as e:
            print(f"❌ Error fetching opponent: {e}")
        return None

class UserNotificationConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        # Allow anonymous connections for now (but they won't trigger online status)
        self.user_id = None
        if self.scope["user"].is_authenticated:
            self.user_id = self.scope["user"].id
            self.user_group_name = f'user_{self.user_id}'
            
            # Join user-specific group for notifications
            await self.channel_layer.group_add(
                self.user_group_name,
                self.channel_name
            )
            
            # Update user online status
            await self.update_user_status(True)
            
            # Notify all users globally about online status change
            await self.channel_layer.group_send(
                'global_notifications',
                {
                    'type': 'user_status_update',
                    'user': {
                        'id': self.user_id,
                        'username': self.scope["user"].username,
                        'is_online': True
                    }
                }
            )
            
            print(f"🔔 User {self.user_id} connecting to notifications")
        else:
            print(f"🔔 Anonymous user connecting to notifications")
        
        # Also join global group
        await self.channel_layer.group_add('global_notifications', self.channel_name)
        
        await self.accept()
        print(f"✅ Notification connection accepted")

    async def disconnect(self, close_code):
        if hasattr(self, 'user_group_name'):
            await self.channel_layer.group_discard(
                self.user_group_name,
                self.channel_name
            )
            
            # Notify all users globally about offline status
            await self.channel_layer.group_send(
                'global_notifications',
                {
                    'type': 'user_status_update',
                    'user': {
                        'id': self.user_id,
                        'is_online': False
                    }
                }
            )
            
            # Update user offline status
            await self.update_user_status(False)

    @database_sync_to_async
    def update_user_status(self, is_online):
        if self.scope["user"].is_authenticated:
            from django.contrib.auth import get_user_model
            User = get_user_model()
            try:
                user = User.objects.get(id=self.scope["user"].id)
                user.is_online = is_online
                user.save()
            except User.DoesNotExist:
                pass

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

    async def call_invitation(self, event):
        """Handle incoming call signal"""
        await self.send(text_data=json.dumps({
            'type': 'call_invitation',
            'data': {
                'caller': event['caller'],
                'room_id': event['room_id'],
                'caller_picture': event.get('caller_picture')
            }
        }))
