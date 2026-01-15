import requests
import json
import random

BASE_URL = "https://chess-game-app-production.up.railway.app/api/auth/"

def test_register():
    print("Testing Registration POST...")
    payload = {
        "username": f"testuser_{random.randint(1000, 9999)}",
        "email": f"test_{random.randint(1000, 9999)}@example.com",
        "password": "testpassword123"
    }
    try:
        response = requests.post(f"{BASE_URL}register/", json=payload)
        print(f"Status Code: {response.status_code}")
        print(f"Response: {response.text}")
        return response.status_code == 201
    except Exception as e:
        print(f"Error: {e}")
        return False

if __name__ == "__main__":
    if test_register():
        print("\n✅ Registration POST successful!")
    else:
        print("\n❌ Registration POST failed!")
