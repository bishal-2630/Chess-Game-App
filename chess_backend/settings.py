"""
Simple Django settings for Termux with Swagger
"""
import os
from pathlib import Path
from decouple import config
import dj_database_url

BASE_DIR = Path(__file__).resolve().parent.parent

# Use config or fallback values
SECRET_KEY = config('SECRET_KEY', default='chess-game-bishal-2024-termux-key')
import time
DEBUG = True
ROOT_URLCONF = 'chess_backend.urls_v7_final'
print(f"🚀 SERVER STARTING - TS: {time.time()} - DEBUG: {DEBUG} - URLCONF: {ROOT_URLCONF}")
ALLOWED_HOSTS = ['*']
RAILWAY_HOSTNAME = config('RAILWAY_STATIC_URL', default='chess-game-app-production.up.railway.app')

# Vercel hostname support
VERCEL_URL = os.environ.get('VERCEL_URL')
if VERCEL_URL:
    ALLOWED_HOSTS.append(VERCEL_URL)

# Flutter Web Directory
FLUTTER_WEB_DIR = BASE_DIR / 'chess_game' / 'build' / 'web'

INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    
    # Third party
    'rest_framework',
    'corsheaders',
    'rest_framework.authtoken',
    'drf_yasg',  
    
    # Local
    'auth_app.apps.AuthAppConfig',
    'channels',
]

MIDDLEWARE = [
    'corsheaders.middleware.CorsMiddleware',
    'django.middleware.security.SecurityMiddleware',
    'whitenoise.middleware.WhiteNoiseMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    # CSRF PROTECTION DISABLED - This is a REST API using JWT authentication
    # CSRF protection is not needed for APIs that use token-based auth (not cookies)
    # Security is provided by: JWT tokens + CORS + HTTPS
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]
print(f"🛠️ ACTIVE MIDDLEWARE: {MIDDLEWARE}")

# REST API Security Configuration (No CSRF needed)
CSRF_COOKIE_SECURE = False
CSRF_USE_SESSIONS = False
CSRF_COOKIE_HTTPONLY = False

# Completely disable CSRF for API
CSRF_COOKIE_SECURE = False
CSRF_USE_SESSIONS = False
CSRF_COOKIE_HTTPONLY = False

SOCIALACCOUNT_PROVIDERS = {
    'google': {
        'SCOPE': ['profile', 'email'],
        'AUTH_PARAMS': {'access_type': 'online'},
        'APP': {
            'client_id': config('GOOGLE_CLIENT_ID', default=''),
            'secret': config('GOOGLE_CLIENT_SECRET', default=''),
        }
    }
}

SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')
USE_X_FORWARDED_HOST = True
USE_X_FORWARDED_PORT = True

# CORS settings
CORS_ALLOW_ALL_ORIGINS = True  
CORS_ALLOW_CREDENTIALS = True

CORS_ALLOWED_ORIGINS = [
    "https://chessgameauth.share.zrok.io",
    "http://chessgameauth.share.zrok.io",
    "http://localhost:8080",
    "http://127.0.0.1:8080",
    "https://chess-game-app-production.up.railway.app",
    "https://chess-game-app-delta.vercel.app",
    "https://*.vercel.app",
]

# For Swagger to work with zrok
CORS_ALLOW_HEADERS = [
    'accept',
    'accept-encoding',
    'authorization',
    'content-type',
    'dnt',
    'origin',
    'user-agent',
    'x-csrftoken',
    'x-requested-with',
]

# ROOT_URLCONF is already set at the top

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [BASE_DIR / 'public'],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

WSGI_APPLICATION = 'chess_backend.wsgi.application'
ASGI_APPLICATION = 'chess_backend.asgi.application'

CHANNEL_LAYERS = {
    "default": {
        "BACKEND": "channels.layers.InMemoryChannelLayer"
    }
}

DATABASES = {
    'default': dj_database_url.config(
        default=f"sqlite:///{BASE_DIR / 'db.sqlite3'}",  
        conn_max_age=600,
        conn_health_checks=True,
    )
}

AUTH_PASSWORD_VALIDATORS = [
    {'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator'},
    {'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator'},
    {'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator'},
    {'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator'},
]

AUTH_USER_MODEL = 'auth_app.User'
LANGUAGE_CODE = 'en-us'
TIME_ZONE = 'UTC'
USE_I18N = True
USE_TZ = True

STATIC_URL = 'static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'
if not STATIC_ROOT.exists():
    STATIC_ROOT.mkdir(parents=True, exist_ok=True)

WHITENOISE_USE_FINDERS = True
STATICFILES_STORAGE = 'whitenoise.storage.CompressedStaticFilesStorage'

try:
    FLUTTER_WEB_PATH = BASE_DIR / 'chess_game' / 'build' / 'web'
    if FLUTTER_WEB_PATH.exists():
        STATICFILES_DIRS = [FLUTTER_WEB_PATH]
    else:
        dummy_path = BASE_DIR / "dummy_static"
        dummy_path.mkdir(exist_ok=True)
        STATICFILES_DIRS = [dummy_path]
except Exception as e:
    STATICFILES_DIRS = []

DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'
DEFAULT_FROM_EMAIL = os.environ.get('DEFAULT_FROM_EMAIL', 'kbishal177@gmail.com')
EMAIL_BACKEND = 'django.core.mail.backends.console.EmailBackend'  

from datetime import timedelta
SIMPLE_JWT = {
    'ACCESS_TOKEN_LIFETIME': timedelta(days=1),
    'REFRESH_TOKEN_LIFETIME': timedelta(days=7),
    'ROTATE_REFRESH_TOKENS': True,
    'BLACKLIST_AFTER_ROTATION': True,
    'ALGORITHM': 'HS256',
    'SIGNING_KEY': SECRET_KEY,
}

REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES': [
        'rest_framework_simplejwt.authentication.JWTAuthentication',
    ],
    'DEFAULT_PERMISSION_CLASSES': [
        'rest_framework.permissions.AllowAny',  
    ],
}

SWAGGER_SETTINGS = {
    'SECURITY_DEFINITIONS': {
        'Bearer': {
            'type': 'apiKey',
            'name': 'Authorization',
            'in': 'header',
            'description': 'JWT Authorization header using the Bearer scheme. Example: "Bearer {token}"'
        }
    },
    'USE_SESSION_AUTH': False,
    'VALIDATOR_URL': None,
    'DEFAULT_API_URL': 'https://chessgameauth.share.zrok.io',
}

CSRF_TRUSTED_ORIGINS = [
    "https://chessgameauth.share.zrok.io",
    "http://chessgameauth.share.zrok.io",  
    "https://*.zrok.io",
    "https://*.share.zrok.io",
    "https://*.ngrok.io",
    "https://*.loca.lt",
    "http://localhost:8080",  
    "http://127.0.0.1:8080",
    "https://chessgameapp.up.railway.app",
    "https://chess-game-app-production.up.railway.app",
    "https://chessgame-wheat.vercel.app",
    "https://chess-game-app-delta.vercel.app",
    "https://*.vercel.app",
]

SWAGGER_UI_OAUTH2_REDIRECT_URL = 'https://chessgameauth.share.zrok.io/swagger/oauth2-redirect.html'

# GHOSTBUSTER CONFIG
CSRF_FAILURE_VIEW = 'auth_app.views.csrf_failure'
APPEND_SLASH = False
DEPLOYMENT_ID = "V7_EXORCIST_FINAL"
print(f"👻 GHOSTBUSTER ACTIVE - ID: {DEPLOYMENT_ID}")