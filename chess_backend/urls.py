from django.contrib import admin
from django.urls import path, include, re_path
from rest_framework import permissions
from drf_yasg.views import get_schema_view
from drf_yasg import openapi
from . import views

# Swagger Schema View
schema_view = get_schema_view(
    openapi.Info(
        title="Chess Game Authentication API",
        default_version='v1',
        description="Complete authentication system for Chess Game by Bishal\n\nGitHub: https://github.com/bishal-2630/Chess-Game-App",
        terms_of_service="https://github.com/bishal-2630/Chess-Game-App",
        contact=openapi.Contact(email="kbishal177@gmail.com"),
        license=openapi.License(name="MIT License"),
    ),
    public=True,
    permission_classes=(permissions.AllowAny,),
)

urlpatterns = [
    # Admin
    path('admin/', admin.site.urls),
    
    # API
    path('api/auth/', include('auth_app.urls')),
    
    # Swagger URLs
    path('swagger/', schema_view.with_ui('swagger', cache_timeout=0), name='schema-swagger-ui'),
    path('redoc/', schema_view.with_ui('redoc', cache_timeout=0), name='schema-redoc'),
    path('swagger.json/', schema_view.without_ui(cache_timeout=0), name='schema-json'),
    
    # Root URL - Serve Flutter app
    path('', views.serve_flutter_app, name='serve_flutter_app'),
]
