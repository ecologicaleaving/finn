#!/bin/bash
# Finn - Run Development

# Exit on error
set -e

# Load environment
if [ ! -f .env.dev ]; then
    echo "❌ .env.dev not found!"
    echo "Copy .env.example to .env.dev and configure it"
    exit 1
fi

# Copy to .env (flutter_dotenv reads from .env)
cp .env.dev .env

echo "💰 Starting Finn (Development)"
echo "📡 Supabase: $(grep SUPABASE_URL .env.dev | cut -d'=' -f2)"
echo "✅ Using HTTPS - No tunnel needed!"
echo ""

flutter run
