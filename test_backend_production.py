import requests
import json

BASE_URL = "https://chess-game-app-production.up.railway.app/api/auth/"

def test_health():
    print("Testing Backend Health...")
    try:
        response = requests.get(f"{BASE_URL}health/")
        print(f"Status Code: {response.status_code}")
        print(f"Response: {json.dumps(response.json(), indent=2)}")
        return response.status_code == 200
    except Exception as e:
        print(f"Error: {e}")
        return False

if __name__ == "__main__":
    if test_health():
        print("\n✅ Backend is UP and Healthy!")
    else:
        print("\n❌ Backend is DOWN or Unreachable!")
