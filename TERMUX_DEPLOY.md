# Termux Deployment Guide

This guide covers how to run the Chess Game backend on Termux and connect it to your production PostgreSQL database.

## 1. Install System Dependencies
Run these commands in Termux to ensure you have the necessary libraries for Python and PostgreSQL:
```bash
pkg update && pkg upgrade
pkg install build-essential python-dev binutils rust postgresql openssl
```

## 2. Install Python Packages
```bash
pip install -r requirements.txt
```

## 3. Connect to PostgreSQL (Railway)
To use your production users:
1. Copy your **Public Database URL** from the Railway dashboard.
2. Set it in Termux:
   ```bash
   export DATABASE_URL="your-railway-db-url"
   ```
   *(Tip: Add this line to your `~/.bashrc` to keep it active)*

## 4. Run Server
```bash
python manage.py runserver 0.0.0.0:8000
```

## 5. Expose with zrok
```bash
zrok share reserved chessgameauth
```
