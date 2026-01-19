import requests
import json

BASE_URL = "https://chessgameapp.up.railway.app"

def debug_probe():
    print(f"--- DEBUG PROBE: {BASE_URL} ---")
    
    endpoints = [
        "/api/auth/health-check-new/",
        "/api/auth/health/",
        "/api/auth/final-bypass/"
    ]
    
    for ep in endpoints:
        print(f"\nChecking {ep}...")
        try:
            r = requests.get(f"{BASE_URL}{ep}", timeout=5)
            print(f"STATUS: {r.status_code}")
            print(f"HEADERS: {dict(r.headers)}")
            try:
                print(f"BODY: {r.text[:500]}")
            except:
                print("BODY: <binary or unreadable>")
        except Exception as e:
            print(f"ERROR: {e}")
    print("\n--- PROBE COMPLETE ---")

if __name__ == "__main__":
    debug_probe()
