import asyncio
import json
import sys

try:
    import websockets
except ImportError:
    print("❌ 'websockets' library not found. Please run: pip install websockets")
    sys.exit(1)

async def test_connection():
    uri = "ws://127.0.0.1:8000/ws/call/testroom/"
    print(f"Connecting to {uri}...")
    try:
        async with websockets.connect(uri) as websocket:
            print("✅ Connected successfully!")
            
            # Send offer
            await websocket.send(json.dumps({"type": "offer", "sdp": "fake_sdp"}))
            print("Sent offer message.")
            
            print("Waiting for messages (ctrl+c to exit)...")
            # We won't receive anything back unless another client joins, but staying connected proves it works.
            # Let's just exit after a short delay to prove stability
            await asyncio.sleep(1)
            print("✅ Connection stable.")
            
    except Exception as e:
        print(f"❌ Connection failed: {e}")
        print("Ensure the backend is running: python start_backend.py")

if __name__ == "__main__":
    asyncio.run(test_connection())
