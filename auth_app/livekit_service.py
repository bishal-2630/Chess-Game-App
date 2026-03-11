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
        Records a RoomComposite layout to an MP4 file stored in S3.
        Requires S3 (or compatible) storage to be configured.
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
        s3_bucket = getattr(settings, 'S3_BUCKET', os.environ.get('S3_BUCKET', ''))
        s3_key = getattr(settings, 'AWS_ACCESS_KEY_ID', os.environ.get('AWS_ACCESS_KEY_ID', ''))
        s3_secret = getattr(settings, 'AWS_SECRET_ACCESS_KEY', os.environ.get('AWS_SECRET_ACCESS_KEY', ''))
        s3_region = getattr(settings, 'AWS_S3_REGION_NAME', os.environ.get('AWS_S3_REGION_NAME', 'us-east-1'))
        s3_endpoint = getattr(settings, 'AWS_S3_ENDPOINT_URL', os.environ.get('AWS_S3_ENDPOINT_URL', ''))
        
        if not (s3_bucket and s3_key and s3_secret):
            print("⚠️ [LiveKit] S3 storage NOT configured (S3_BUCKET, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY required).")
            print("💡 [LiveKit] Skipping recording — add S3 credentials to your environment to enable recordings.")
            return False

        print(f"📦 [LiveKit] Using S3 storage: {s3_bucket}")
        
        s3_config = {
            "access_key": s3_key,
            "secret": s3_secret,
            "region": s3_region,
            "bucket": s3_bucket,
            "key": filename,
        }
        if s3_endpoint:
            # Used for S3-compatible storage like Cloudflare R2, MinIO, Backblaze B2, etc.
            s3_config["endpoint"] = s3_endpoint
            s3_config["force_path_style"] = True
        
        payload = {
            "room_name": room_name,
            "layout": "grid",
            "file_outputs": [
                {
                    "file_type": 0,  # MP4 (default)
                    "filepath": filename,
                    "s3": s3_config,
                }
            ]
        }
        
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }
        
        print(f"🎬 [LiveKit] Archival recording trigger for room: {room_name}")
        try:
            response = requests.post(endpoint, headers=headers, json=payload, timeout=15)
            if response.status_code == 200:
                egress_id = response.json().get('egress_id')
                print(f"✅ [LiveKit] Recording started: {egress_id}")
                return True
            else:
                print(f"❌ [LiveKit] Egress failed ({response.status_code})")
                print(f"📝 Response Body: {response.text}")
                return False
        except Exception as e:
            print(f"❌ [LiveKit] Recording trigger error: {e}")
            return False
