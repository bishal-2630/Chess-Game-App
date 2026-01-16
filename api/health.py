"""
Health check endpoint for Vercel deployment
"""
import json
from http.server import BaseHTTPRequestHandler

class handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        response = {"status": "healthy", "message": "Chess Game API is running"}
        self.wfile.write(json.dumps(response).encode())
        return
