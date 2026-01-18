#!/usr/bin/env python
import os
import django

# Set up Django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'chess_backend.settings')
django.setup()

from auth_app.models import User

def test_password():
    try:
        user = User.objects.get(email='kbishal177@gmail.com')
        print(f'User found: {user.username}, ID: {user.id}')
        
        # Test various passwords
        test_passwords = ['test123', 'Bishal123', 'password', '123456']
        
        for pwd in test_passwords:
            result = user.check_password(pwd)
            print(f'Password check for "{pwd}": {result}')
        
        # Set a known password for testing
        user.set_password('test123')
        user.save()
        print(f'After setting password to "test123": {user.check_password("test123")}')
        
    except User.DoesNotExist:
        print('User not found')

if __name__ == '__main__':
    test_password()
