from django.apps import AppConfig
import os
import sys

class AuthAppConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'auth_app'

    def ready(self):
        # Auto-migration disabled for Vercel stability
        pass
        # if 'migrate' in sys.argv or 'makemigrations' in sys.argv or 'collectstatic' in sys.argv:
        #     return
        # ...
