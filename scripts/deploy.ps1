# Hybrid Deployment Script for Windows
# Deploys Flutter Web to Vercel and WebSocket Backend to Railway

param(
    [string]$RailwayHost = ""
)

Write-Host "🚀 Starting Hybrid Deployment..." -ForegroundColor Green

# Check if Railway CLI is installed
try {
    railway --version | Out-Null
} catch {
    Write-Host "❌ Railway CLI not found. Install with: npm install -g @railway/cli" -ForegroundColor Red
    exit 1
}

# Check if Vercel CLI is installed
try {
    vercel --version | Out-Null
} catch {
    Write-Host "❌ Vercel CLI not found. Install with: npm i -g vercel" -ForegroundColor Red
    exit 1
}

# Build Flutter Web
Write-Host "📱 Building Flutter Web app..." -ForegroundColor Blue
Set-Location chess_game
flutter clean
flutter pub get
flutter build web --web-renderer canvaskit

# Copy build files to root
Write-Host "📋 Copying build files..." -ForegroundColor Blue
Copy-Item -Recurse -Force "build\web\*" "..\"
Set-Location ..

# Deploy to Railway (Backend)
Write-Host "🚂 Deploying WebSocket backend to Railway..." -ForegroundColor Blue
railway up

# Get Railway URL
$RailwayUrl = railway domains | Select-Object -First 1 | ForEach-Object { $_.Split(' ')[0] }
Write-Host "🔗 Railway URL: $RailwayUrl" -ForegroundColor Yellow

# Update Flutter config with Railway URL
if ($RailwayHost -eq "") {
    $RailwayHost = $RailwayUrl
}

Write-Host "⚙️ Updating Flutter configuration..." -ForegroundColor Blue
(Get-Content "chess_game\lib\services\config.dart") -replace 'your-railway-app\.railway\.app', $RailwayHost | Set-Content "chess_game\lib\services\config.dart"

# Rebuild with updated config
Write-Host "🔄 Rebuilding with updated configuration..." -ForegroundColor Blue
Set-Location chess_game
flutter build web --web-renderer canvaskit
Copy-Item -Recurse -Force "build\web\*" "..\"
Set-Location ..

# Deploy to Vercel (Frontend)
Write-Host "🌐 Deploying Flutter Web to Vercel..." -ForegroundColor Blue
vercel --prod

Write-Host "✅ Deployment Complete!" -ForegroundColor Green
Write-Host "📱 Frontend: Check Vercel dashboard for URL" -ForegroundColor Cyan
Write-Host "🚂 Backend: $RailwayUrl" -ForegroundColor Cyan
Write-Host "🔗 WebSocket: wss://$RailwayUrl/ws/call/" -ForegroundColor Cyan
