import requests
import json

def check_endpoint(name, url, method="GET", payload=None):
    print(f"\n🔍 Probing {name}: {url}")
    try:
        if method == "POST":
            response = requests.post(url, json=payload, timeout=10)
        else:
            response = requests.get(url, timeout=10)
        
        print(f"  Status: {response.status_code}")
        print(f"  Deployment-ID: {response.headers.get('X-Deployment-ID', 'MISSING (Ghost!)')}")
        if response.status_code == 200:
            try:
                print(f"  Body: {json.dumps(response.json(), indent=2)}")
            except:
                print(f"  Body: {response.text[:100]}...")
        else:
            print(f"  Error: {response.text[:100]}...")
        return response
    except Exception as e:
        print(f"  ❌ Failed: {str(e)}")
        return None

# DIAGNOSTIC SUITE
print("🚀 V7 EXORCIST DIAGNOSTIC START 🚀")

domain = "https://chess-game-app-production.up.railway.app"
print(f"\n🌐 TESTING DOMAIN: {domain}")

# 1. New Health Check
check_endpoint("V7 Health", f"{domain}/health-v7-exorcist/")

# 2. Ghost Check
check_endpoint("Ghost Check", f"{domain}/ghost-check/")

# 3. Final Login Bypass V2
payload = {"email": "kbishal177@gmail.com", "password": "test123"}
check_endpoint("Login Bypass V2", f"{domain}/api/auth/final-bypass-v2/", "POST", payload)
