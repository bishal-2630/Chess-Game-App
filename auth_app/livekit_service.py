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
    def get_participant_count(room_name):
        """
        Queries LiveKit API to get the number of participants currently in the room.
        Used as a fallback trigger for recording when webhooks are unreliable.
        """
        import requests
        livekit_url = getattr(settings, 'LIVEKIT_URL', '')
        base_url = livekit_url.replace('wss://', 'https://').replace('ws://', 'http://')
        endpoint = f"{base_url}/twirp/livekit.RoomService/ListParticipants"
        
        token = LiveKitService.generate_admin_token()
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }
        
        try:
            payload = {"room": room_name}
            response = requests.post(endpoint, headers=headers, json=payload, timeout=5)
            if response.status_code == 200:
                participants = response.json().get('participants', [])
                count = len(participants)
                print(f"📊 [LiveKit] Room {room_name} has {count} active participants.")
                return count
            return 0
        except Exception as e:
            print(f"⚠️ [LiveKit] Error checking participant count: {e}")
            return 0

    @staticmethod
    def start_recording(room_name):
        """
        Triggers archival recording for the room via LiveKit Egress.
        Records a RoomComposite layout to an MP4 file stored in Backblaze B2 (S3 compatible).
        """
        import requests
        import json
        import os
        
        livekit_url = getattr(settings, 'LIVEKIT_URL', '')
        # Convert wss:// to https://
        base_url = livekit_url.replace('wss://', 'https://').replace('ws://', 'http://')
        endpoint = f"{base_url}/twirp/livekit.Egress/StartRoomCompositeEgress"
        
        token = LiveKitService.generate_admin_token()
        
        timestamp = int(time.time())
        filename = f"recording_{room_name}_{timestamp}.mp4"
        
        # S3 Configuration from settings or environment
        s3_bucket = getattr(settings, 'S3_BUCKET', '') or 'chess-recordings'
        s3_key = getattr(settings, 'AWS_ACCESS_KEY_ID', '') or '00535ce0ea2aa8f0000000001'
        s3_secret = getattr(settings, 'AWS_SECRET_ACCESS_KEY', '') or 'K005HwNL9ZWk6y8ZoaxuAA6isC614Ss'
        s3_region = getattr(settings, 'AWS_S3_REGION_NAME', '') or 'us-east-005'
        s3_endpoint = getattr(settings, 'AWS_S3_ENDPOINT_URL', '') or 'https://s3.us-east-005.backblazeb2.com'
        
        if not (s3_bucket and s3_key and s3_secret):
            print("⚠️ [LiveKit] S3/Backblaze storage NOT configured correctly.")
            return False

        print(f"📦 [LiveKit] Targeted Storage: {s3_bucket} at {s3_endpoint}")
        
        s3_config = {
            "access_key": s3_key,
            "secret": s3_secret,
            "region": s3_region,
            "bucket": s3_bucket,
            "key": filename,
        }
        if s3_endpoint:
            s3_config["endpoint"] = s3_endpoint
            s3_config["force_path_style"] = True
        
        payload = {
            "room_name": room_name,
            "layout": "grid",
            "file_outputs": [
                {
                    "file_type": 0,  # MP4
                    "filepath": filename,
                    "s3": s3_config,
                }
            ]
        }
        
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }
        
        print(f"🎬 [LiveKit] Attempting to start recorder for: {room_name}")
        try:
            response = requests.post(endpoint, headers=headers, json=payload, timeout=15)
            if response.status_code == 200:
                egress_id = response.json().get('egress_id')
                print(f"✅ [LiveKit] Recording STARTED: {egress_id}")
                return True
            else:
                print(f"❌ [LiveKit] Egress Failed ({response.status_code}): {response.text}")
                return False
        except Exception as e:
            print(f"❌ [LiveKit] Recording Trigger EXCEPTION: {e}")
            return False
