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

class FirebaseAuthSerializer(serializers.Serializer):
    firebase_token = serializers.CharField(required=True)