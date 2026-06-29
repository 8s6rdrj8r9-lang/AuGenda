#!/bin/bash
# validate-oauth.sh
# Pre-build script to ensure Google OAuth client ID is not a placeholder.

CLIENT_ID=$(grep -o 'YOUR_CLIENT_ID_HERE' AuGenda/GoogleOAuth.swift || true)

if [ -n "$CLIENT_ID" ]; then
    echo "❌ ERROR: Google OAuth client ID is still a placeholder!"
    echo "   Set AUGENDA_GOOGLE_CLIENT_ID in your Xcode build settings."
    exit 1
fi

echo "✅ Google OAuth client ID is configured."
exit 0
