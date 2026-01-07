# chess/start_backend.py - SIMPLIFIED VERSION
import subprocess
import sys
import os
import time
from pathlib import Path

def main():
    print("🚀 Starting Django Backend for Chess Game")
    print("="*50)
    
    # Get current file location (Flutter project)
    current_dir = Path(__file__).parent.absolute()
    print(f"📁 Flutter project: {current_dir}")
    
    # Django is in sibling folder
    django_dir = current_dir.parent / "chess_backend"
    print(f"📁 Django backend: {django_dir}")
    
    if not (django_dir / "manage.py").exists():
        print(f"❌ ERROR: manage.py not found at {django_dir}")
        print("   Make sure Django project is at: D:\\Chess Game\\chess_backend")
        input("Press Enter to exit...")
        return
    
    # Command to start Django
    cmd = [sys.executable, "manage.py", "runserver", "0.0.0.0:8000"]
    
    print(f"\n⚙️  Starting: {' '.join(cmd)}")
    print(f"🌐 Server URL: http://127.0.0.1:8000")
    print(f"📧 OTP API: http://127.0.0.1:8000/api/auth/send-otp/")
    print("\n" + "="*50)
    
    try:
        # Start Django
        process = subprocess.Popen(
            cmd,
            cwd=str(django_dir),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            universal_newlines=True,
            bufsize=1
        )
        
        # Read output
        print("\n📡 Django Output:")
        print("-" * 30)
        
        # Wait and check if started
        for i in range(15):
            line = process.stdout.readline()
            if line:
                print(line.rstrip())
                if "Starting development server" in line:
                    print("\n✅ Django backend started successfully!")
                    print("📧 OTP email system is READY")
                    print("\n🛑 Press Ctrl+C to stop the backend")
                    break
            time.sleep(1)
            
            # Check if process died
            if process.poll() is not None:
                print("❌ Django process died!")
                break
        
        # Keep running
        try:
            while True:
                line = process.stdout.readline()
                if line:
                    print(line.rstrip())
                time.sleep(0.1)
        except KeyboardInterrupt:
            print("\n🛑 Stopping Django backend...")
            process.terminate()
            
    except Exception as e:
        print(f"❌ Error: {e}")

if __name__ == "__main__":
    main()