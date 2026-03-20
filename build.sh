#!/usr/bin/env bash
# exit on error
set -o errexit

# --- Flutter Setup ---
FLUTTER_VERSION="3.24.0" # Match your local version if possible
FLUTTER_SDK_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"

if [ ! -d "flutter" ]; then
  echo "Downloading Flutter SDK..."
  curl -o flutter.tar.xz $FLUTTER_SDK_URL
  tar xf flutter.tar.xz
  rm flutter.tar.xz
fi

export PATH="$PATH:$(pwd)/flutter/bin"

echo "Flutter version:"
flutter --version

# --- Flutter Build ---
cd chess_game
flutter pub get
flutter build web --release
cd ..

# --- Python Setup ---
pip install -r requirements.txt

python manage.py collectstatic --no-input
python manage.py migrate
