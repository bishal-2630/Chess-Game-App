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
    def generate_admin_token():
        """Generates an admin token for for API access."""
        api_key = getattr(settings, 'LIVEKIT_API_KEY', 'APImrhGecyNFG7p')
        api_secret = getattr(settings, 'LIVEKIT_API_SECRET', 'CEf97PsPDAFW6aVRtmS1NlMid5LQZZ3xWKJyfQPqQ5g')
        
        now = int(time.time())
        payload = {
            "exp": now + 600,
            "iss": api_key,
            "jti": f"admin-{now}",
            "video": {
                "roomCreate": True,
                "roomList": True,
                "roomRecord": True,
                "roomAdmin": True,
                "canPublish": True,
                "canSubscribe": True,
            }
        }
        return jwt.encode(payload, api_secret, algorithm='HS256')

    @staticmethod
    def start_recording(room_name):
        """
        Triggers archival recording for the room via LiveKit Egress.
        Records a RoomComposite layout to an MP4 file.
        """
        import requests
        import json
        
        livekit_url = getattr(settings, 'LIVEKIT_URL', '')
        # Convert wss:// to https://
        base_url = livekit_url.replace('wss://', 'https://').replace('ws://', 'http://')
        endpoint = f"{base_url}/twirp/livekit.Egress/StartRoomCompositeEgress"
        
        token = LiveKitService.generate_admin_token()
        
        timestamp = int(time.time())
        filename = f"recording_{room_name}_{timestamp}.mp4"
        
        payload = {
            "room_name": room_name,
            "layout": "grid", # Standard layout for organization records
            "file_outputs": [{
                "filepath": filename,
                # Note: Cloud providers like S3 would be configured here if available
            }]
        }
        
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }
        
        print(f"🎬 [LiveKit] Archival recording trigger for room: {room_name}")
        try:
            response = requests.post(endpoint, headers=headers, json=payload, timeout=10)
            if response.status_code == 200:
                print(f"✅ [LiveKit] Recording started: {response.json().get('egress_id')}")
                return True
            else:
                print(f"❌ [LiveKit] Egress failed ({response.status_code}): {response.text}")
                return False
        except Exception as e:
            print(f"❌ [LiveKit] Recording trigger error: {e}")
            return False
