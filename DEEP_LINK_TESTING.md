# Deep Linking Test Instructions

## Testing Deep Links

### Option 1: Using ADB (Android Debug Bridge)

**Test Custom Scheme (chess://):**
```bash
adb shell am start -W -a android.intent.action.VIEW -d "chess://play"
```

**Test HTTPS Deep Link:**
```bash
adb shell am start -W -a android.intent.action.VIEW -d "https://positive-brianne-self2630-c40dbd11.koyeb.app/play"
```

**Test Game Deep Link:**
```bash
adb shell am start -W -a android.intent.action.VIEW -d "chess://game/123"
```

### Option 2: Using HTML Test File

Create a file `test_deeplinks.html` with the following content:

```html
<!DOCTYPE html>
<html>
<head>
    <title>Chess Deep Link Test</title>
    <style>
        body { font-family: Arial; padding: 20px; }
        a { display: block; margin: 10px 0; padding: 15px; background: #007bff; color: white; text-decoration: none; border-radius: 5px; }
        a:hover { background: #0056b3; }
    </style>
</head>
<body>
    <h1>Chess Deep Link Test</h1>
    <p>Click the links below to test deep linking:</p>
    
    <a href="chess://play">Open Chess (Custom Scheme)</a>
    <a href="chess://game/123">Open Game #123 (Custom Scheme)</a>
    <a href="https://positive-brianne-self2630-c40dbd11.koyeb.app/play">Open Chess (HTTPS)</a>
    <a href="https://positive-brianne-self2630-c40dbd11.koyeb.app/game/456">Open Game #456 (HTTPS)</a>
</body>
</html>
```

Then:
1. Transfer this file to your Android device
2. Open it in Chrome browser
3. Click the links to test deep linking

### Option 3: Using Chrome Browser

1. Open Chrome on your Android device
2. Type in the address bar: `chess://play`
3. Press Enter
4. Android should prompt you to open the Chess app

### Expected Behavior

When you click a deep link:
1. Android shows a dialog: "Open with Chess Bishal"
2. You tap "Chess Bishal"
3. The app opens automatically
4. If logged in, the WebView screen loads with authentication
5. If not logged in, you're redirected to login screen

### Debugging

If deep links don't work:
1. Check logcat for deep link messages:
   ```bash
   adb logcat | grep -i "deep\|chess\|link"
   ```

2. Verify intent filters are registered:
   ```bash
   adb shell dumpsys package com.example.chess_bishal | grep -A 10 "android.intent.action.VIEW"
   ```

3. Check if app is installed:
   ```bash
   adb shell pm list packages | grep chess
   ```

### Testing Cookie Injection

1. Login to the Flutter app
2. Click a deep link to open WebView
3. In the WebView screen, tap the debug icon (bug icon in app bar)
4. Check that cookies are listed
5. Verify `sessionid` cookie is present

### Manual Verification Checklist

- [ ] Custom scheme `chess://play` opens the app
- [ ] HTTPS link `https://...koyeb.app/play` opens the app
- [ ] Game links with ID work correctly
- [ ] WebView loads after deep link
- [ ] Cookies are injected (check debug info)
- [ ] Authentication works in WebView
- [ ] App opens from browser link
- [ ] Fallback to browser works when app not installed
