from django.apps import AppConfig
import os
import sys

class AuthAppConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'auth_app'

    def ready(self):
        # Auto-run migrations on startup, but avoid recursion if already migrating
        if 'migrate' in sys.argv or 'makemigrations' in sys.argv or 'collectstatic' in sys.argv:
            return

        print("--- AuthApp: Attempting Auto-Migration ---")
        try:
            from django.core.management import call_command
            # Ensure tables are created
            call_command('migrate', interactive=False)
            print("--- AuthApp: Auto-Migration Successful ---")
        except Exception as e:
            print(f"--- AuthApp: Auto-Migration Failed: {e} ---")
            import traceback
            print(traceback.format_exc())
