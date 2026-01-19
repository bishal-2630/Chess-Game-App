import requests
import json

url = "https://chess-game-app-production.up.railway.app/api/auth/final-bypass-v2/"
payload = {
    "email": "kbishal177@gmail.com",
    "password": "test123"
}
headers = {
    "Content-Type": "application/json"
}

print(f"DEBUG: Probing {url}")
try:
    response = requests.post(url, json=payload, headers=headers, timeout=10)
    print(f"STATUS CODE: {response.status_code}")
    print(f"HEADERS: {response.headers}")
    try:
        print(f"BODY: {json.dumps(response.json(), indent=2)}")
    except:
        print(f"BODY (TEXT): {response.text[:500]}")
except Exception as e:
    print(f"ERROR: {e}")
