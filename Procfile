web: python manage.py migrate --noinput && python manage.py collectstatic --noinput && PYTHONPATH=. daphne chess_backend.asgi:application --port $PORT --bind 0.0.0.0
