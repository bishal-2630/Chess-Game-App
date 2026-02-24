from rest_framework import status, permissions
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken
from django.contrib.auth import get_user_model
from django.contrib.auth import login
from requests import RequestException
import requests
import json
from drf_yasg.utils import swagger_auto_schema

User = get_user_model()

class GoogleLoginView(APIView):
    """
    Google Sign-In endpoint for Django authentication
    """
    permission_classes = [permissions.AllowAny]
    
    @swagger_auto_schema(auto_schema=None)
    def post(self, request):
        access_token = request.data.get('access_token')
        id_token = request.data.get('id_token')
        
        if not access_token and not id_token:
            return Response({
                'error': 'Both access_token and id_token are required'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        try:
            # Verify Google token using Google's API
            google_api_url = "https://www.googleapis.com/oauth2/v2/userinfo"
            headers = {'Authorization': f'Bearer {access_token}'}
            
            response = requests.get(google_api_url, headers=headers, timeout=10)
            
            if response.status_code != 200:
                return Response({
                    'error': 'Failed to verify Google token'
                }, status=status.HTTP_401_UNAUTHORIZED)
            
            google_user_data = response.json()
            google_email = google_user_data.get('email')
            google_name = google_user_data.get('name', '')
            google_picture = google_user_data.get('picture', '')
            google_id = google_user_data.get('id')
            
            if not google_email:
                return Response({
                    'error': 'Email not found in Google account'
                }, status=status.HTTP_400_BAD_REQUEST)
            
            # Get or create user
            try:
                user = User.objects.get(email=google_email)
                # Update user info if needed
                if not user.first_name or not user.last_name:
                    name_parts = google_name.split()
                    user.first_name = name_parts[0] if len(name_parts) > 0 else ''
                    user.last_name = ' '.join(name_parts[1:]) if len(name_parts) > 1 else ''
                    user.save()
                    
            except User.DoesNotExist:
                # Create new user
                username = google_email.split('@')[0]
                base_username = username
                counter = 1
                
                # Ensure unique username
                while User.objects.filter(username=username).exists():
                    username = f"{base_username}{counter}"
                    counter += 1
                
                name_parts = google_name.split()
                first_name = name_parts[0] if len(name_parts) > 0 else ''
                last_name = ' '.join(name_parts[1:]) if len(name_parts) > 1 else ''
                
                user = User.objects.create_user(
                    username=username,
                    email=google_email,
                    password=None,  
                    first_name=first_name,
                    last_name=last_name,
                    google_id=google_id,
                    profile_picture=google_picture
                )
            
            
            # Generate JWT tokens
            refresh = RefreshToken.for_user(user)
            
            # Prepare user data for response
            user_data = {
                'id': user.id,
                'username': user.username,
                'email': user.email,
                'first_name': user.first_name,
                'last_name': user.last_name,
                'google_id': getattr(user, 'google_id', None),
                'profile_picture': getattr(user, 'profile_picture', None),
                'is_guest': False
            }
            
            return Response({
                'success': True,
                'user': user_data,
                'access': str(refresh.access_token),
                'refresh': str(refresh),
                'message': 'Google login successful'
            }, status=status.HTTP_200_OK)
            
        except RequestException as e:
            return Response({
                'error': f'Network error: {str(e)}'
            }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
        except Exception as e:
            return Response({
                'error': f'Authentication failed: {str(e)}'
            }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
