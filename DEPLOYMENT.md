# Hybrid Deployment Guide

This project uses a hybrid deployment architecture:
- **Frontend**: Flutter Web hosted on Vercel
- **Backend**: Django Channels WebSocket server hosted on Railway

## Architecture

```
Flutter Web App (Vercel) → WebSocket Backend (Railway)
```

## Deployment Steps

### 1. Deploy WebSocket Backend to Railway

1. **Create Railway Account**
   - Sign up at [railway.app](https://railway.app)
   - Connect your GitHub repository

2. **Configure Environment Variables**
   In Railway dashboard, set:
   ```
   PYTHONUNBUFFERED=1
   DJANGO_SETTINGS_MODULE=chess_backend.settings
   ALLOWED_HOSTS=your-railway-app.railway.app
   ```

3. **Deploy**
   - Railway will automatically detect the Python project
   - Uses `railway.toml` and `Procfile` for configuration
   - WebSocket server will be available at: `wss://your-app.railway.app`

### 2. Update Flutter Configuration

1. **Update WebSocket URL**
   Edit `chess_game/lib/services/config.dart`:
   ```dart
   static const String _railwayHost = 'your-actual-railway-app.railway.app';
   ```

2. **Build Flutter Web**
   ```bash
   cd chess_game
   flutter build web --web-renderer canvaskit
   ```

3. **Copy Build Files**
   ```bash
   cp -r build/web/* ../
   ```

### 3. Deploy Frontend to Vercel

1. **Install Vercel CLI**
   ```bash
   npm i -g vercel
   ```

2. **Deploy**
   ```bash
   vercel --prod
   ```

## Environment Configuration

### Development
- WebSocket: `ws://127.0.0.1:8000/ws/call/`
- API: `http://127.0.0.1:8000/api/auth/`

### Production
- WebSocket: `wss://your-railway-app.railway.app/ws/call/`
- API: `https://your-railway-app.railway.app/api/auth/`

## Files Created/Modified

### Railway Configuration
- `railway.toml` - Railway build configuration
- `Procfile` - Railway process configuration

### Vercel Configuration
- `vercel.json` - Updated to serve static files only

### Flutter Configuration
- `chess_game/lib/services/config.dart` - Updated for configurable backend URL

### Environment
- `.env.example` - Template for environment variables

## Testing the Deployment

1. **Backend Test**
   ```bash
   wscat -c wss://your-railway-app.railway.app/ws/call/testroom/
   ```

2. **Frontend Test**
   - Visit your Vercel URL
   - Check browser console for WebSocket connection

## Troubleshooting

### WebSocket Connection Issues
- Check Railway logs for errors
- Verify CORS settings in Django
- Ensure WebSocket URL uses `wss://` for production

### Build Issues
- Run `flutter clean` before building
- Check `requirements.txt` for missing dependencies
- Verify Railway build logs

### CORS Issues
Add to Django settings:
```python
CORS_ALLOWED_ORIGINS = [
    "https://your-vercel-app.vercel.app",
]
```
