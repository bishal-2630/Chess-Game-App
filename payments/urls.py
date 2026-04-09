from django.urls import path
from .views import CreateCheckoutSessionView, stripe_webhook

urlpatterns = [
    path('create-checkout-session/', CreateCheckoutSessionView.as_view(), name='create-checkout-session'),
    path('webhook/', stripe_webhook, name='stripe-webhook'),
]
