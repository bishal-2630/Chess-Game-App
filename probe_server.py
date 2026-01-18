
import requests
import json

BASE_URL = "https://chessgameapp.up.railway.app"

def probe():
    print(f"🕵️ Probing {BASE_URL}...\n")

    # 1. Check final-bypass (Should be 404 if updated, or 200/403 if old)
    bypass_url = f"{BASE_URL}/api/auth/final-bypass/"
    print(f"checking {bypass_url}...")
    try:
        r_bypass = requests.post(bypass_url, json={"email": "test", "password": "test"}, timeout=10)
        print(f"Status: {r_bypass.status_code}")
        if r_bypass.status_code == 403:
            print("⚠️  Got 403 Forbidden - CSRF Middleware is likely ACTIVE.")
            if "CSRF verification failed" in r_bypass.text:
                print("   Confirmed: CSRF Error Page received.")
        elif r_bypass.status_code == 404:
            print("✅ Got 404 Not Found - Endpoint successfully removed (New Code!).")
        else:
            print(f"   Got code: {r_bypass.status_code}")
    except Exception as e:
        print(f"   Error: {e}")

    print("-" * 20)

    # 2. Check Health Endpoint (Look for markers)
    health_url = f"{BASE_URL}/api/auth/health/"
    print(f"checking {health_url}...")
    try:
        r_health = requests.get(health_url, timeout=10)
        print(f"Status: {r_health.status_code}")
        if r_health.status_code == 200:
            data = r_health.json()
            print(json.dumps(data, indent=2))
        else:
            print("Health check failed.")
    except Exception as e:
        print(f"   Error: {e}")

if __name__ == "__main__":
    probe()
