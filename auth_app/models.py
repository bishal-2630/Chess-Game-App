import secrets
from datetime import datetime, timedelta
from django.db import models
from django.contrib.auth.models import AbstractUser
import uuid

class User(AbstractUser):
    firebase_uid = models.CharField(max_length=255, unique=True, null=True, blank=True)
    email_verified = models.BooleanField(default=False)
    phone_number = models.CharField(max_length=20, null=True, blank=True)
    
    def __str__(self):
        return self.email

class OTP(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE)
    otp_code = models.CharField(max_length=6)
    purpose = models.CharField(max_length=50)  
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    is_used = models.BooleanField(default=False)
    
    def is_valid(self):
        return datetime.now() < self.expires_at and not self.is_used
    
    def mark_used(self):
        self.is_used = True
        self.save()
    
    @classmethod
    def generate_otp(cls, user, purpose='password_reset', expiry_minutes=10):
        # Generate 6-digit numeric OTP (not base32)
        otp_code = ''.join(secrets.choice('0123456789') for _ in range(6))
        expires_at = datetime.now() + timedelta(minutes=expiry_minutes)
        
        # Invalidate previous OTPs for same user and purpose
        cls.objects.filter(user=user, purpose=purpose, is_used=False).update(is_used=True)
        
        return cls.objects.create(
            user=user,
            otp_code=otp_code,
            purpose=purpose,
            expires_at=expires_at
        )

class PasswordResetToken(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE)
    token = models.UUIDField(default=uuid.uuid4, unique=True)
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    is_used = models.BooleanField(default=False)
    
    def is_valid(self):
        return datetime.now() < self.expires_at and not self.is_used