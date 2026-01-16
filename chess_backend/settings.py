"""
Simple Django settings for Termux with Swagger
"""
import os
from pathlib import Path
from decouple import config
import dj_database_url

BASE_DIR = Path(__file__).resolve().parent.parent

# Use config or fallback values
try:
    SECRET_KEY = config('SECRET_KEY', default='chess-game-bishal-2024-termux-key')
    DEBUG = config('DEBUG', default=False, cast=bool)
    ALLOWED_HOSTS = config('ALLOWED_HOSTS', default='*').split(',')
    RAILWAY_HOSTNAME = config('RAILWAY_STATIC_URL', default='chess-game-app-production.up.railway.app')
    if RAILWAY_HOSTNAME:
        ALLOWED_HOSTS.append(RAILWAY_HOSTNAME)
    
    # Vercel hostname support
    VERCEL_URL = os.environ.get('VERCEL_URL')
    if VERCEL_URL:
        ALLOWED_HOSTS.append(VERCEL_URL)
        ALLOWED_HOSTS.append(f'*.{VERCEL_URL.split(".", 1)[-1]}' if '.' in VERCEL_URL else VERCEL_URL)

# Debugging Paths
except:
    SECRET_KEY = 'chess-game-bishal-2024-termux-key'
    DEBUG = False
    ALLOWED_HOSTS = ['*']

# Add Vercel URLs to ALLOWED_HOSTS if not already added
VERCEL_URL = os.environ.get('VERCEL_URL')
if VERCEL_URL and VERCEL_URL not in ALLOWED_HOSTS:
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
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

# ZROK HTTPS FIXES - ADD THESE LINES:
SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')
USE_X_FORWARDED_HOST = True
USE_X_FORWARDED_PORT = True

# CORS settings - ADD SPECIFIC ORIGINS FOR ZROK and Vercel
CORS_ALLOW_ALL_ORIGINS = True  # Keep this for testing
CORS_ALLOW_CREDENTIALS = True

# More specific CORS settings (optional but recommended)
CORS_ALLOWED_ORIGINS = [
    "https://chessgameauth.share.zrok.io",
    "http://chessgameauth.share.zrok.io",
    "http://localhost:8080",
    "http://127.0.0.1:8080",
    "https://chess-game-app-production.up.railway.app",
    "https://*.vercel.app",
]

# Add Vercel URL to CORS_ALLOWED_ORIGINS
VERCEL_URL = os.environ.get('VERCEL_URL')
if VERCEL_URL:
    vercel_origin = f"https://{VERCEL_URL}" if not VERCEL_URL.startswith('http') else VERCEL_URL
    if vercel_origin not in CORS_ALLOWED_ORIGINS:
        CORS_ALLOWED_ORIGINS.append(vercel_origin)

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

ROOT_URLCONF = 'chess_backend.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [BASE_DIR / 'chess_game' / 'build' / 'web'],
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
    {
        'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator',
    },
]

AUTH_USER_MODEL = 'auth_app.User'

LANGUAGE_CODE = 'en-us'
TIME_ZONE = 'UTC'
USE_I18N = True
USE_TZ = True

STATIC_URL = 'static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'
# Ensure directory exists to silence warning
if not STATIC_ROOT.exists():
    STATIC_ROOT.mkdir(parents=True, exist_ok=True)

# Use Finders to serve files even if collectstatic fails
WHITENOISE_USE_FINDERS = True
# Use simple storage to avoid manifest errors
STATICFILES_STORAGE = 'whitenoise.storage.CompressedStaticFilesStorage'

STATICFILES_DIRS = [
    BASE_DIR / 'chess_game' / 'build' / 'web',
]

DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'

DEFAULT_FROM_EMAIL = os.environ.get('DEFAULT_FROM_EMAIL', 'kbishal177@gmail.com')

# Firebase Configuration 
FIREBASE_API_KEY = config('FIREBASE_API_KEY', default='')
FIREBASE_WEB_API_KEY = config('FIREBASE_WEB_API_KEY', default='')


# JWT Configuration
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

# Swagger Settings 
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

# For Zrok/ngrok and Vercel
CSRF_TRUSTED_ORIGINS = [
    "https://chessgameauth.share.zrok.io",
    "http://chessgameauth.share.zrok.io",  
    "https://*.zrok.io",
    "https://*.share.zrok.io",
    "https://*.ngrok.io",
    "https://*.loca.lt",
    "http://localhost:8080",  
    "http://127.0.0.1:8080",
    #"https://chess-game-app-production.up.railway.app",
    "https://chessgame-wheat.vercel.app",
    "https://*.vercel.app",
]

# Add Vercel URL to CSRF_TRUSTED_ORIGINS
VERCEL_URL = os.environ.get('VERCEL_URL')
if VERCEL_URL:
    vercel_origin = f"https://{VERCEL_URL}" if not VERCEL_URL.startswith('http') else VERCEL_URL
    if vercel_origin not in CSRF_TRUSTED_ORIGINS:
        CSRF_TRUSTED_ORIGINS.append(vercel_origin)

# SWAGGER TO WORK WITH ZROK
SWAGGER_UI_OAUTH2_REDIRECT_URL = 'https://chessgameauth.share.zrok.io/swagger/oauth2-redirect.html'