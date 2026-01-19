
import requests
import json
from datetime import datetime

BASE_URL = "https://chessgameapp.up.railway.app"

def check():
    with open("probe_output.txt", "w", encoding="utf-8") as f:
        f.write("-" * 30 + "\n")
        f.write(f"🕵️ CHECKING: {BASE_URL}\n")
        f.write("-" * 30 + "\n")

        # 1. Check Legacy Endpoint (Should be 404)
        f.write("1. Checking Legacy Endpoint (final-bypass)...\n")
        try:
            r = requests.post(f"{BASE_URL}/api/auth/final-bypass/", json={"x":"y"}, timeout=5)
            if r.status_code == 403:
                 f.write(f"❌ STATUS: {r.status_code} (Forbidden)\n")
                 f.write("   ⚠️  FAIL: Server still has the old endpoint active.\n")
            elif r.status_code == 404:
                 f.write(f"✅ STATUS: {r.status_code} (Not Found)\n")
                 f.write("   🎉 SUCCESS: New code is live!\n")
            else:
                 f.write(f"   STATUS: {r.status_code}\n")
        except Exception as e:
            f.write(f"   Error: {e}\n")

        f.write("\n2. Checking Server Health...\n")
        try:
            r = requests.get(f"{BASE_URL}/api/auth/health/", timeout=5)
            if r.status_code == 200:
                data = r.json()
                ts = data.get('timestamp')
                f.write(f"   Server Time: {ts}\n")
                f.write(f"   Full Response: {json.dumps(data)}\n")
            else:
                f.write(f"   Status: {r.status_code}\n")
        except Exception as e:
            f.write(f"   Error: {e}\n")
        f.write("-" * 30 + "\n")
    print("Probe finished. Check probe_output.txt")

if __name__ == "__main__":
    check()
