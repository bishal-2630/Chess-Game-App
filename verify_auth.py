
import requests
import sys
import random
import string

# Configuration
BASE_URL = "https://chessgameapp.up.railway.app"
REGISTER_URL = f"{BASE_URL}/api/auth/register/"
LOGIN_URL = f"{BASE_URL}/api/auth/login/"

def random_string(length=8):
    return ''.join(random.choices(string.ascii_lowercase, k=length))

def run_verification():
    print(f"🔍 Verifying Auth System against: {BASE_URL}")
    
    # 1. Generate Random User
    username = f"test_{random_string()}"
    email = f"{username}@example.com"
    password = "SafePassword123!"
    
    print(f"\n👤 Generated User:\nUsername: {username}\nEmail: {email}")

    # 2. Test Registration
    print("\n[1/2] Testing Registration...")
    try:
        reg_response = requests.post(REGISTER_URL, json={
            "username": username,
            "email": email,
            "password": password
        })
        
        if reg_response.status_code == 201:
            print("✅ Registration Successful!")
        else:
            print(f"❌ Registration Failed: {reg_response.status_code}")
            print(reg_response.text)
            return
    except Exception as e:
        print(f"❌ Registration Request Failed: {e}")
        return

    # 3. Test Login
    print("\n[2/2] Testing Login...")
    try:
        login_response = requests.post(LOGIN_URL, json={
            "email": email,
            "password": password
        })
        
        if login_response.status_code == 200:
            print("✅ Login Successful!")
            tokens = login_response.json().get('tokens', {})
            if 'access' in tokens:
                print("🔑 Tokens received correctly.")
            else:
                print("⚠️ Login succeeded but tokens missing from response.")
        else:
            print(f"❌ Login Failed: {login_response.status_code}")
            print(login_response.text)
            return

    except Exception as e:
        print(f"❌ Login Request Failed: {e}")
        return
        
    print("\n🎉 VERIFICATION COMPLETE: Authentication system is working correctly.")

if __name__ == "__main__":
    run_verification()
