#!/bin/bash

# Hybrid Deployment Script
# Deploys Flutter Web to Vercel and WebSocket Backend to Railway

set -e

echo "🚀 Starting Hybrid Deployment..."

# Check if Railway CLI is installed
if ! command -v railway &> /dev/null; then
    echo "❌ Railway CLI not found. Install with: npm install -g @railway/cli"
    exit 1
fi

# Check if Vercel CLI is installed
if ! command -v vercel &> /dev/null; then
    echo "❌ Vercel CLI not found. Install with: npm i -g vercel"
    exit 1
fi

# Build Flutter Web
echo "📱 Building Flutter Web app..."
cd chess_game
flutter clean
flutter pub get
flutter build web --web-renderer canvaskit

# Copy build files to root
echo "📋 Copying build files..."
cp -r build/web/* ../
cd ..

# Deploy to Railway (Backend)
echo "🚂 Deploying WebSocket backend to Railway..."
railway up

# Get Railway URL
RAILWAY_URL=$(railway domains | head -n 1 | awk '{print $1}')
echo "🔗 Railway URL: $RAILWAY_URL"

# Update Flutter config with Railway URL
echo "⚙️ Updating Flutter configuration..."
sed -i "s/your-railway-app.railway.app/$RAILWAY_URL/g" chess_game/lib/services/config.dart

# Rebuild with updated config
echo "🔄 Rebuilding with updated configuration..."
cd chess_game
flutter build web --web-renderer canvaskit
cp -r build/web/* ../
cd ..

# Deploy to Vercel (Frontend)
echo "🌐 Deploying Flutter Web to Vercel..."
vercel --prod

echo "✅ Deployment Complete!"
echo "📱 Frontend: Check Vercel dashboard for URL"
echo "🚂 Backend: $RAILWAY_URL"
echo "🔗 WebSocket: wss://$RAILWAY_URL/ws/call/"
