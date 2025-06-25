#!/bin/bash

echo "Updating system packages (optional, press Ctrl+C to skip)..."
sleep 1
if [ "$(uname)" == "Linux" ]; then
  sudo apt-get update && sudo apt-get upgrade -y
elif [ "$(uname)" == "Darwin" ]; then
  brew update
fi

echo "Checking for Node.js and npm..."
if ! command -v node &> /dev/null; then
    echo "Node.js is not installed. Please install Node.js and try again."
    exit 1
fi
if ! command -v npm &> /dev/null; then
    echo "npm is not installed. Please install npm and try again."
    exit 1
fi

echo "Checking for cloudflared..."
if ! command -v cloudflared &> /dev/null; then
    echo "cloudflared is not installed. Please install it from https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation/"
    exit 1
fi

echo "Installing/updating npm dependencies..."
npm install

echo "Starting Node.js server in the background..."
node server.js > server.log 2>&1 &
SERVER_PID=$!

sleep 2

echo "Do you want to use a custom Cloudflare Tunnel domain? (y/N)"
read USE_CUSTOM
if [[ "$USE_CUSTOM" =~ ^[Yy]$ ]]; then
    echo "Make sure you have set up a named tunnel and configured your domain in Cloudflare."
    echo "Enter your tunnel name:"
    read TUNNEL_NAME
    echo "Running: cloudflared tunnel run $TUNNEL_NAME"
    cloudflared tunnel run "$TUNNEL_NAME"
else
    echo "Starting Cloudflare Tunnel with a random subdomain..."
    cloudflared tunnel --url http://localhost:3000
fi

trap "kill $SERVER_PID" EXIT
