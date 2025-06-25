#!/bin/bash

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
    echo "cloudflared not found, installing..."
    OS=$(uname -s)
    ARCH=$(uname -m)
    if [[ "$OS" == "Linux" ]]; then
      if [[ "$ARCH" == "x86_64" ]]; then
        URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
      elif [[ "$ARCH" == "aarch64" ]]; then
        URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
      elif [[ "$ARCH" == "armv7l" ]]; then
        URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm"
      else
        echo "Unsupported architecture: $ARCH"
        exit 1
      fi
    elif [[ "$OS" == "Darwin" ]]; then
      URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-amd64"
    else
      echo "Unsupported OS: $OS"
      exit 1
    fi

    curl -L -o cloudflared $URL
    chmod +x cloudflared
    sudo mv cloudflared /usr/local/bin/

    if ! command -v cloudflared &> /dev/null; then
      echo "cloudflared installation failed. Please install manually."
      exit 1
    fi
    echo "cloudflared installed successfully."
else
    echo "cloudflared is already installed"
fi

echo "Installing/updating npm dependencies..."
npm install

echo "Starting Node.js server in the background..."
node server.js > server.log 2>&1 &
SERVER_PID=$!

sleep 3

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
    # Use 127.0.0.1 to avoid IPv6 issues
    cloudflared tunnel --url http://127.0.0.1:3000 > cloudflared.log 2>&1 &
    TUNNEL_PID=$!

    # Wait for the tunnel to initialize and extract the public URL
    sleep 8
    PUBLIC_URL=$(grep -o 'https://[-a-zA-Z0-9.]*trycloudflare.com' cloudflared.log | head -n 1)
    if [ -z "$PUBLIC_URL" ]; then
      echo "Could not find public URL. Check cloudflared.log for errors."
    else
      echo "Your public URL: $PUBLIC_URL"
      echo "Share this link with your target."
    fi

    # Wait for background processes (server and tunnel)
    wait $TUNNEL_PID
fi

trap "kill $SERVER_PID" EXIT
