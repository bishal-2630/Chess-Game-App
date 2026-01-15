#!/bin/bash
echo "--- Starting Startup Script ---"

# Run Migrations
echo "--- Running Migrations ---"
python manage.py makemigrations --noinput
python manage.py migrate --noinput

# Collect Static
echo "--- Collecting Static Files ---"
python manage.py collectstatic --noinput

# Start Server
echo "--- Starting Server ---"
PYTHONPATH=. daphne chess_backend.asgi:application --port $PORT --bind 0.0.0.0
