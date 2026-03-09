from jose import jwt
import time
from django.conf import settings

class LiveKitService:
    @staticmethod
    def generate_token(room_name, participant_name):
        """
        Generates a LiveKit JWT token using python-jose for maximum stability.
        Avoids dependency issues with the full livekit SDK on some servers.
        """
        # Hardcoded fallbacks to bypass server-side settings reload issues
        api_key = getattr(settings, 'LIVEKIT_API_KEY', 'APImrhGecyNFG7p')
        api_secret = getattr(settings, 'LIVEKIT_API_SECRET', 'CEf97PsPDAFW6aVRtmS1NlMid5LQZZ3xWKJyfQPqQ5g')
        
        if not api_key or not api_secret:
            print("⚠️ LIVEKIT_API_KEY or LIVEKIT_API_SECRET not set!")
            return None

        # Standard LiveKit Claims
        # https://docs.livekit.io/realtime/access-tokens/#the-structure-of-an-access-token
        now = int(time.time())
        print(f"🛠️ [LiveKit] Generating token for Room: {room_name}, Participant: {participant_name}")
        payload = {
            "exp": now + 3600,  # 1 hour expiry
            "iss": api_key,
            "sub": participant_name,
            "jti": f"{participant_name}-{now}",
            "video": {
                "roomJoin": True,
                "room": room_name,
                "canPublish": True,
                "canSubscribe": True,
                "canPublishData": True
            },
            "name": participant_name,
            "metadata": ""
        }
        
        try:
            # Sign using HS256 as required by LiveKit
            token = jwt.encode(payload, api_secret, algorithm='HS256')
            return token
        except Exception as e:
            print(f"❌ Error encoding LiveKit token: {e}")
            return None

    @staticmethod
    def start_recording(room_name):
        """
        Placeholder for triggering recording. 
        Recording requires a separate Egress setup in LiveKit.
        """
        print(f"🎬 [LiveKit] Token generated for room: {room_name}. Recording trigger ready if Egress is configured.")
        pass
