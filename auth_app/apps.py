from django.apps import AppConfig
import os
import sys

class AuthAppConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'auth_app'

    def ready(self):
        # Only run migrations in the main process, not in reloaders or management commands
        if os.environ.get('RUN_MAIN') == 'true' or 'daphne' in sys.argv or 'runserver' in sys.argv:
            print("--- AuthApp: Triggering Auto-Migration ---")
            try:
                from django.core.management import call_command
                call_command('migrate', interactive=False)
                print("--- AuthApp: Auto-Migration Successful ---")
            except Exception as e:
                print(f"--- AuthApp: Auto-Migration Failed: {e} ---")
