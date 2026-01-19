import time
import requests
import json

BASE_URL = "https://chessgameapp.up.railway.app"

def check():
    print(f"Starting poll at {time.ctime()}")
    start = time.time()
    while time.time() - start < 300: # 5 mins
        try:
            # Check Health
            try:
                r = requests.get(f"{BASE_URL}/api/auth/health-new/", timeout=5)
                if r.status_code == 200:
                    data = r.json()
                    # Check for our specific version string
                    ver = data.get('deploy_version', '')
                    if 'v3-forced-update' in ver:
                        with open("probe_result.txt", "w") as f:
                            f.write("SUCCESS\n")
                            f.write(json.dumps(data))
                        print("SUCCESS: Version match!")
                        return
            except Exception as e:
                print(f"Health check error: {e}")

            # Check Legacy Endpoint (Expect 404)
            try:
                r2 = requests.post(f"{BASE_URL}/api/auth/final-bypass/", json={"x":"y"}, timeout=5)
                if r2.status_code == 404:
                     with open("probe_result.txt", "w") as f:
                            f.write("SUCCESS_404\n")
                     print("SUCCESS: 404 on final-bypass!")
                     return
            except Exception as e:
                 print(f"Endpoint check error: {e}")
                 
        except Exception as e:
            print(f"Loop error: {e}")
        
        time.sleep(15)

    with open("probe_result.txt", "w") as f:
        f.write("TIMEOUT\n")
    print("TIMEOUT")

if __name__ == "__main__":
    check()
