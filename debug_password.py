#!/usr/bin/env python3
import os
import sys
import django

# Add the project root to Python path
sys.path.append('/app')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'chess_backend.settings')
django.setup()

from auth_app.models import User

# Test user creation and password
email = "testdebug@example.com"
username = "testdebug"
password = "test123"

# Delete existing test user if exists
User.objects.filter(email=email).delete()

# Create new user
user = User.objects.create_user(
    username=username,
    email=email,
    password=password
)

print(f"Created user: {user.username}, email: {user.email}")

# Test password check
if user.check_password(password):
    print("✅ Password check works!")
else:
    print("❌ Password check failed!")

# Test authentication
from django.contrib.auth import authenticate
auth_user = authenticate(username=email, password=password)
if auth_user:
    print("✅ Authentication works!")
else:
    print("❌ Authentication failed!")

# Test with username
auth_user2 = authenticate(username=username, password=password)
if auth_user2:
    print("✅ Username authentication works!")
else:
    print("❌ Username authentication failed!")
