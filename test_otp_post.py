import requests
import json

BASE_URL = "https://chess-game-app-production.up.railway.app/api/auth/"

def test_send_otp():
    print("Testing Send OTP POST...")
    # Use an email that exists in the system or just any email to see if it connects
    payload = {
        "email": "kbishal177@gmail.com"
    }
    try:
        response = requests.post(f"{BASE_URL}send-otp/", json=payload)
        print(f"Status Code: {response.status_code}")
        print(f"Response: {response.text}")
        return response.status_code == 200
    except Exception as e:
        print(f"Error: {e}")
        return False

if __name__ == "__main__":
    if test_send_otp():
        print("\n✅ Send OTP POST successful (or at least reachable)!")
    else:
        print("\n❌ Send OTP POST failed!")
