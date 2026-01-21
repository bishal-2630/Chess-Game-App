from datetime import datetime, timedelta
from django.db import models
from django.contrib.auth.models import AbstractUser
from django.contrib.auth.hashers import make_password, check_password
from django.conf import settings
import uuid
import os
import requests

class User(AbstractUser):
    email = models.EmailField(unique=True, blank=False)
    firebase_uid = models.CharField(max_length=255, unique=True, null=True, blank=True)
    google_id = models.CharField(max_length=255, unique=True, null=True, blank=True)
    profile_picture = models.URLField(max_length=500, null=True, blank=True)
    email_verified = models.BooleanField(default=False)
    phone_number = models.CharField(max_length=20, null=True, blank=True)
    is_online = models.BooleanField(default=False)
    last_seen = models.DateTimeField(null=True, blank=True)
    current_room = models.CharField(max_length=100, null=True, blank=True)

    
    
    def __str__(self):
        return self.email

class OTP(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE)
    otp_code = models.CharField(max_length=255)  # Increased for hash storage
    purpose = models.CharField(max_length=50)  
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    is_used = models.BooleanField(default=False)
    
    def is_valid(self, raw_otp=None):
        from django.utils import timezone
        # Use timezone.now() if settings.USE_TZ=True (which it is)
        now = timezone.now() if settings.USE_TZ else datetime.now()
        
        valid_basic = now < self.expires_at and not self.is_used
        if raw_otp:
            return valid_basic and check_password(raw_otp, self.otp_code)
        return valid_basic
    
    def mark_used(self):
        self.is_used = True
        self.save()
        
    def send_otp(self):
        """Sends the OTP code via Resend API."""
        try:
            api_key = os.environ.get('RESEND_API_KEY', 're_fomKSfPW_BHFU1ayggtd7FtvvCrSj5GJd')
            
            if not api_key:
                print(f"❌ RESEND_API_KEY missing. Printing OTP for {self.user.email}: {getattr(self, 'plain_code', 'UNKNOWN')}")
                return False

            # Use plain_code if available (should be set during generate_otp)
            code_to_send = getattr(self, 'plain_code', None)
            if not code_to_send:
                print(f"❌ Error: Plain code missing for OTP email to {self.user.email}")
                return False

            response = requests.post(
                "https://api.resend.com/emails",
                headers={
                    "Authorization": f"Bearer {api_key}",
                    "Content-Type": "application/json",
                },
                json={
                    "from": "Chess Game <onboarding@resend.dev>",
                    "to": [self.user.email],
                    "subject": f"{self.purpose.replace('_', ' ').title()} OTP - Chess Game",
                    "html": f"""
                    <div style="font-family: sans-serif; padding: 20px; border: 1px solid #eee; border-radius: 10px;">
                        <h2 style="color: #333;">Chess Game Verification</h2>
                        <p>Your OTP code is:</p>
                        <h1 style="color: #007bff; letter-spacing: 5px;">{code_to_send}</h1>
                        <p>This code will expire in 10 minutes.</p>
                        <p>If you didn't request this, please ignore this email.</p>
                        <hr style="border: 0; border-top: 1px solid #eee; margin: 20px 0;">
                        <p style="font-size: 12px; color: #999;">Best regards,<br>Bishal's Chess Game Team</p>
                    </div>
                    """
                },
                timeout=10
            )
            
            if response.status_code in [200, 201]:
                print(f"✅ OTP email sent to {self.user.email}")
                return True
            else:
                print(f"❌ Resend API failed ({response.status_code}): {response.text}")
                return False
        except Exception as e:
            print(f"❌ Error sending OTP email: {str(e)}")
            return False
    
    @classmethod
    def generate_otp(cls, user, purpose='password_reset', expiry_minutes=10):
        import secrets
        # Generate 6-digit numeric OTP
        plain_otp = ''.join(secrets.choice('0123456789') for _ in range(6))
        hashed_otp = make_password(plain_otp)
        expires_at = datetime.now() + timedelta(minutes=expiry_minutes)
        
        # Invalidate previous OTPs for same user and purpose
        cls.objects.filter(user=user, purpose=purpose, is_used=False).update(is_used=True)
        
        otp_obj = cls.objects.create(
            user=user,
            otp_code=hashed_otp,
            purpose=purpose,
            expires_at=expires_at
        )
        
        # Attach the plain code temporarily so it can be sent via email
        otp_obj.plain_code = plain_otp
        return otp_obj

class PasswordResetToken(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE)
    token = models.UUIDField(default=uuid.uuid4, unique=True)
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    is_used = models.BooleanField(default=False)
    
    def is_valid(self):
        return datetime.now() < self.expires_at and not self.is_used

class GameInvitation(models.Model):
    STATUS_CHOICES = [
        ('pending', 'Pending'),
        ('accepted', 'Accepted'),
        ('declined', 'Declined'),
        ('cancelled', 'Cancelled'),
    ]
    
    sender = models.ForeignKey(User, on_delete=models.CASCADE, related_name='sent_invitations')
    receiver = models.ForeignKey(User, on_delete=models.CASCADE, related_name='received_invitations')
    room_id = models.CharField(max_length=100)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='pending')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        unique_together = ['sender', 'receiver', 'room_id']
    
    def __str__(self):
        return f"{self.sender.username} → {self.receiver.username} ({self.status})"