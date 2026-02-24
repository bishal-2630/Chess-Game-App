from django.contrib import admin
from django.contrib.auth.admin import UserAdmin
from .models import User, GameInvitation, OTP

@admin.register(User)
class CustomUserAdmin(UserAdmin):
    list_display = ['username', 'email', 'is_online', 'last_seen', 'current_room', 'is_staff']
    list_filter = ['is_online', 'is_staff', 'is_superuser', 'email_verified']
    search_fields = ['username', 'email']
    
    fieldsets = UserAdmin.fieldsets + (
        ('Additional Info', {
            'fields': ('firebase_uid', 'google_id', 'profile_picture', 'email_verified', 
                      'phone_number', 'is_online', 'last_seen', 'current_room')
        }),
    )

@admin.register(GameInvitation)
class GameInvitationAdmin(admin.ModelAdmin):
    list_display = ['sender', 'receiver', 'room_id', 'status', 'created_at']
    list_filter = ['status', 'created_at']
    search_fields = ['sender__username', 'receiver__username', 'room_id']

@admin.register(OTP)
class OTPAdmin(admin.ModelAdmin):
    list_display = ['user', 'purpose', 'created_at', 'expires_at', 'is_used']
    list_filter = ['purpose', 'is_used', 'created_at']
    search_fields = ['user__email', 'user__username']
