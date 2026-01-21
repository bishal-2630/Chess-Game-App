import os
import django
from django.conf import settings

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'chess_backend.settings')
django.setup()

db_config = settings.DATABASES['default']
print(f"DB_ENGINE: {db_config['ENGINE']}")
print(f"DB_NAME: {db_config['NAME']}")

from django.contrib.auth import get_user_model
User = get_user_model()
print(f"TOTAL_USERS: {User.objects.count()}")
