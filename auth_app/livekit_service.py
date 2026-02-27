from django.conf import settings
from datetime import timedelta

class LiveKitService:
    @staticmethod
    def generate_token(room_name, participant_name):
        """Generate a LiveKit access token using python-jose JWT signing."""
        try:
            from jose import jwt
            import time

            api_key = settings.LIVEKIT_API_KEY
            api_secret = settings.LIVEKIT_API_SECRET

            now = int(time.time())
            payload = {
                "iss": api_key,
                "sub": participant_name,
                "iat": now,
                "exp": now + 3600,  # 1 hour
                "video": {
                    "roomJoin": True,
                    "room": room_name,
                    "canPublish": True,
                    "canSubscribe": True,
                }
            }
            token = jwt.encode(payload, api_secret, algorithm="HS256")
            return token
        except Exception as e:
            print(f"❌ [LiveKit] Token generation error: {e}")
            raise

    @staticmethod
    def start_recording(room_name):
        """Placeholder for recording - skipped for now to avoid dependency issues."""
        print(f"🎬 [LiveKit] Recording placeholder for room: {room_name}")
