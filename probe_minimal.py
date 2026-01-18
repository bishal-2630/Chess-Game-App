
import requests
import json
from datetime import datetime

BASE_URL = "https://chessgameapp.up.railway.app"

def check():
    print("-" * 30)
    print(f"🕵️ CHECKING: {BASE_URL}")
    print("-" * 30)

    # 1. Check Legacy Endpoint (Should be 404)
    print("1. Checking Legacy Endpoint (final-bypass)...")
    try:
        r = requests.post(f"{BASE_URL}/api/auth/final-bypass/", json={"x":"y"}, timeout=5)
        if r.status_code == 403:
             print(f"❌ STATUS: {r.status_code} (Forbidden)")
             print("   ⚠️  FAIL: Server still has the old endpoint active.")
        elif r.status_code == 404:
             print(f"✅ STATUS: {r.status_code} (Not Found)")
             print("   🎉 SUCCESS: New code is live!")
        else:
             print(f"   STATUS: {r.status_code}")
    except Exception as e:
        print(f"   Error: {e}")

    print("\n2. Checking Server Health...")
    try:
        r = requests.get(f"{BASE_URL}/api/auth/health/", timeout=5)
        if r.status_code == 200:
            data = r.json()
            ts = data.get('timestamp')
            print(f"   Server Time: {ts}")
            print(f"   Full Response: {json.dumps(data)}")
        else:
            print(f"   Status: {r.status_code}")
    except Exception as e:
        print(f"   Error: {e}")
    print("-" * 30)

if __name__ == "__main__":
    check()
