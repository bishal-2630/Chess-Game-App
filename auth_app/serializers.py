from rest_framework import serializers
from django.contrib.auth import get_user_model
from .models import OTP, PasswordResetToken
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError

User = get_user_model()

class EmailSerializer(serializers.Serializer):
    email = serializers.EmailField(required=True)

class OTPSerializer(serializers.Serializer):
    email = serializers.EmailField(required=True)
    otp = serializers.CharField(max_length=6, required=True)

class PasswordResetSerializer(serializers.Serializer):
    email = serializers.EmailField(required=True)
    otp = serializers.CharField(max_length=6, required=True)
    new_password = serializers.CharField(required=True, write_only=True)
    confirm_password = serializers.CharField(required=True, write_only=True)
    
    def validate(self, data):
        if data['new_password'] != data['confirm_password']:
            raise serializers.ValidationError("Passwords do not match")
        
        try:
            validate_password(data['new_password'])
        except ValidationError as e:
            raise serializers.ValidationError(list(e.messages))
        
        return data

class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = [
            'id', 'username', 'email', 'first_name', 'last_name', 
            'profile_picture', 'email_verified', 'is_online', 
            'last_seen', 'current_room', 'wins', 'draws', 'losses'
        ]

class TokenSerializer(serializers.Serializer):
    access = serializers.CharField()
    refresh = serializers.CharField()

class RegisterSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, min_length=6)
    
    class Meta:
        model = User
        fields = ['username', 'email', 'password']

class LoginSerializer(serializers.Serializer):
    email = serializers.EmailField()
    password = serializers.CharField(write_only=True)

class LogoutSerializer(serializers.Serializer):
    refresh = serializers.CharField()

class GuestRegisterSerializer(serializers.Serializer):
    username = serializers.CharField()

class AuthResponseSerializer(serializers.Serializer):
    success = serializers.BooleanField()
    message = serializers.CharField()
    user = UserSerializer(required=False)
    tokens = TokenSerializer(required=False)

# class FirebaseAuthSerializer(serializers.Serializer):
#     firebase_token = serializers.CharField(required=True)