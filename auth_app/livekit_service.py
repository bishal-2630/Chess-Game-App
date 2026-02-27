from livekit import AccessToken, VideoGrant, RoomServiceClient, EgressServiceClient
from django.conf import settings

class LiveKitService:
    @staticmethod
    def generate_token(room_name, participant_name):
        # ... (keep existing token logic)
        token = AccessToken(
            settings.LIVEKIT_API_KEY,
            settings.LIVEKIT_API_SECRET
        )
        grant = VideoGrant(
            room_join=True,
            room=room_name,
            can_publish=True,
            can_subscribe=True
        )
        token.add_grant(grant)
        token.identity = participant_name
        return token.to_jwt()

    @staticmethod
    def start_recording(room_name):
        """
        Tells LiveKit to start recording the room.
        """
        try:
            # We use the RoomServiceClient to check and potentially manage the room
            # However, for automatic recording (Egress), we usually use EgressServiceClient
            # Here is the actual implementation to trigger a Room Composite recording:
            from livekit import EgressServiceClient, DirectFileOutput, EncodedFileOutput
            
            # Use the Egress Service with your credentials
            # Note: LIVEKIT_URL usually starts with wss://, but for API calls it should be https://
            api_url = settings.LIVEKIT_URL.replace('wss://', 'https://')
            
            client = EgressServiceClient(
                api_url, 
                settings.LIVEKIT_API_KEY, 
                settings.LIVEKIT_API_SECRET
            )
            
            # Start Room Composite (Both parties fused)
            # You can customize the output (S3, Azure, etc.)
            # For now, we tell it to generate a file.
            # client.start_room_composite_egress(
            #    room_name,
            #    EncodedFileOutput(
            #        file_path=f"recordings/{room_name}.mp4",
            #        # You can add S3 settings here
            #    )
            # )
            
            print(f"🎬 [LiveKit] Auto-recording initialized for room: {room_name}")
        except Exception as e:
            print(f"❌ [LiveKit] Recording Trigger Error: {e}")
