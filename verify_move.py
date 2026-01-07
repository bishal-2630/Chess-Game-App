import asyncio
import json
import io
import sys

try:
    import websockets
except ImportError:
    print("❌ 'websockets' library not found. Please run: pip install websockets")
    sys.exit(1)

# Ensure console supports utf-8
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

async def connect_client(name, room_id):
    uri = f"ws://127.0.0.1:8000/ws/call/{room_id}/"
    print(f"[{name}] Connecting to {uri}...")
    try:
        async with websockets.connect(uri) as websocket:
            print(f"[{name}] ✅ Connected!")
            
            # Keep listening
            async for message in websocket:
                data = json.loads(message)
                # Ignore my own messages (backend should filter, but let's see)
                print(f"[{name}] Received: {data}")
                
                if data.get('type') == 'signaling_message':
                     payload = data.get('message', {})
                     if payload.get('type') == 'move':
                         print(f"[{name}] ♟️  MOVE RECEIVED! {payload}")
                         return # Success for this test

    except Exception as e:
        print(f"[{name}] ❌ Error: {e}")

async def send_move(room_id):
    uri = f"ws://127.0.0.1:8000/ws/call/{room_id}/"
    await asyncio.sleep(2) # Wait for client A to connect
    print(f"[Sender] Connecting to send move...")
    async with websockets.connect(uri) as websocket:
        move_payload = {
            "type": "move",
            "fromRow": 6, "fromCol": 4, 
            "toRow": 4, "toCol": 4, 
            "movedPiece": "wp"
        }
        print(f"[Sender] Sending move: {move_payload}")
        await websocket.send(json.dumps(move_payload))
        print(f"[Sender] Sent!")

async def main():
    room_id = "testroom_move_sync"
    
    # Run a receiving client and a sending client
    listener = connect_client("Listener", room_id)
    sender = send_move(room_id)
    
    await asyncio.gather(listener, sender)

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
