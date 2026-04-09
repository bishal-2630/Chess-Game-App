import stripe
import json
from django.conf import settings
from django.http import JsonResponse, HttpResponse
from django.views.decorators.csrf import csrf_exempt
from rest_framework.views import APIView
from rest_framework.permissions import IsAuthenticated, AllowAny
from rest_framework.response import Response
from .models import Transaction
from django.contrib.auth import get_user_model

User = get_user_model()
stripe.api_key = settings.STRIPE_SECRET_KEY

class CreateCheckoutSessionView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        try:
            # Create a Stripe Checkout Session
            # For simplicity, we'll use a fixed price or a product.
            # In a real app, you might pass a price_id from the frontend.
            
            checkout_session = stripe.checkout.Session.create(
                payment_method_types=['card'],
                line_items=[
                    {
                        'price_data': {
                            'currency': 'usd',
                            'product_data': {
                                'name': 'Chess Pro Upgrade',
                            },
                            'unit_amount': 999, # $9.99
                        },
                        'quantity': 1,
                    },
                ],
                mode='payment',
                success_url=settings.CLIENT_URL + '/payment-success?session_id={CHECKOUT_SESSION_ID}',
                cancel_url=settings.CLIENT_URL + '/payment-cancelled',
                client_reference_id=str(request.user.id),
                metadata={
                    'user_id': request.user.id,
                    'type': 'pro_upgrade'
                }
            )

            # Create a pending transaction
            Transaction.objects.create(
                user=request.user,
                stripe_session_id=checkout_session.id,
                amount=9.99,
                status='pending'
            )

            return Response({'url': checkout_session.url})
        except Exception as e:
            return Response({'error': str(e)}, status=400)

@csrf_exempt
def stripe_webhook(request):
    payload = request.body
    sig_header = request.META.get('HTTP_STRIPE_SIGNATURE')
    event = None

    try:
        event = stripe.Webhook.construct_event(
            payload, sig_header, settings.STRIPE_WEBHOOK_SECRET
        )
    except ValueError as e:
        # Invalid payload
        return HttpResponse(status=400)
    except stripe.error.SignatureVerificationError as e:
        # Invalid signature
        return HttpResponse(status=400)

    # Handle the checkout.session.completed event
    if event['type'] == 'checkout.session.completed':
        session = event['data']['object']
        
        # Get the user ID from metadata
        user_id = session.get('metadata', {}).get('user_id')
        if user_id:
            try:
                user = User.objects.get(id=user_id)
                user.is_pro = True
                user.save()
                
                # Update transaction status
                Transaction.objects.filter(stripe_session_id=session.id).update(status='completed')
                print(f"✅ User {user.email} upgraded to PRO")
            except User.DoesNotExist:
                print(f"❌ User with ID {user_id} not found during webhook")

    return HttpResponse(status=200)
