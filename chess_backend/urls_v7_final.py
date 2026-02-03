from django.contrib import admin
from django.urls import path, include, re_path
from rest_framework.permissions import AllowAny
from drf_yasg.views import get_schema_view
from drf_yasg import openapi
from . import views

# Swagger Schema View
schema_view = get_schema_view(
    openapi.Info(
        title="Chess Game Authentication API",
        default_version='v1',
        description="""
        Complete authentication and signaling system for Chess Game by Bishal.

        ### Real-time Services
        This project uses MQTT and WebSockets for real-time features.
        - **MQTT**: Background notifications and persistent signaling. [Documentation](/api/auth/docs/mqtt/)
        - **WebSockets**: Live in-game signaling and UI updates. [Documentation](/api/auth/docs/websockets/)

        GitHub: https://github.com/bishal-2630/Chess-Game-App
        """,
        terms_of_service="https://github.com/bishal-2630/Chess-Game-App",
        contact=openapi.Contact(email="kbishal177@gmail.com"),
        license=openapi.License(name="MIT License"),
    ),

    public=True,
    permission_classes=(AllowAny,),
)

from django.http import JsonResponse
import time

# API
from auth_app.views import direct_rollback_check

urlpatterns = [
    # Poison Pill Health Checks
    path('health-root-v6/', lambda r: JsonResponse({"root_rollout": "SUCCESS", "v": 6})),
    path('health-v7-exorcist/', lambda r: JsonResponse({
        "status": "V7_EXORCIST_ACTIVE", 
        "deployment_id": "V7_EXORCIST_FINAL",
        "timestamp": time.time()
    })),
    
    # Admin
    path('admin/', admin.site.urls),
    
    # API
    path('api/auth/', include('auth_app.urls_v3')),
    
    # Ghost Check
    path('ghost-check/', direct_rollback_check),
    
    # Swagger URLs
    path('swagger/', schema_view.with_ui('swagger', cache_timeout=0), name='schema-swagger-ui'),
    path('redoc/', schema_view.with_ui('redoc', cache_timeout=0), name='schema-redoc'),
    path('swagger.json/', schema_view.without_ui(cache_timeout=0), name='schema-json'),
    
    # Root URL - Serve Flutter app
    path('', views.serve_flutter_app, name='serve_flutter_app'),
]
