#!/usr/bin/env bash

# Color codes (use printf for best cross-platform compatibility)
CYAN='\033[36m'
YELLOW='\033[33m'
GREEN='\033[32m'
RED='\033[31m'
BOLD='\033[1m'
RESET='\033[0m'

# ASCII Art Logo: DOCPHISH above flipped seawaves
printf "${CYAN}${BOLD}"
cat << "EOF"
██████╗  ██████╗  ██████╗██████╗ ██╗  ██╗██╗███████╗██╗  ██╗
██╔══██╗██╔═══██╗██╔════╝██╔══██╗██║  ██║██║██╔════╝██║  ██║
██║  ██║██║   ██║██║     ██████╔╝███████║██║███████╗███████║
██║  ██║██║   ██║██║     ██╔═══╝ ██╔══██║██║╚════██║██╔══██║
██████╔╝╚██████╔╝╚██████╗██║     ██║  ██║██║███████║██║  ██║
╚═════╝  ╚═════╝  ╚═════╝╚═╝     ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝

_      _      _      _      _      _      _      _
(_.,-''(_.,-''(_.,-''(_.,-''(_.,-''(_.,-''(_.,-''(_.,-''

EOF
printf "${RESET}"

printf "${YELLOW}${BOLD}Welcome to the DocPhish Automated Setup!${RESET}\n"

# Spinner function
spin() {
    local pid=$!
    local delay=0.1
    local spinstr='|/-\'
    while kill -0 $pid 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

printf "${CYAN}Checking for Node.js and npm...${RESET}\n"
if ! command -v node &> /dev/null; then
    printf "${RED}Node.js is not installed. Please install Node.js and try again.${RESET}\n"
    exit 1
fi
if ! command -v npm &> /dev/null; then
    printf "${RED}npm is not installed. Please install npm and try again.${RESET}\n"
    exit 1
fi

printf "${CYAN}Checking for cloudflared...${RESET}\n"
if ! command -v cloudflared &> /dev/null; then
    printf "${YELLOW}cloudflared not found, installing...${RESET}\n"
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
        printf "${RED}Unsupported architecture: $ARCH${RESET}\n"
        exit 1
      fi
    elif [[ "$OS" == "Darwin" ]]; then
      if [[ "$ARCH" == "arm64" ]]; then
        URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-arm64"
      else
        URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-amd64"
      fi
    else
      printf "${RED}Unsupported OS: $OS${RESET}\n"
      exit 1
    fi

    curl -L -o cloudflared $URL
    chmod +x cloudflared
    # Choose install dir based on OS/arch
    if [[ "$OS" == "Darwin" && "$ARCH" == "arm64" ]]; then
      # Apple Silicon Homebrew default bin path
      DEST="/opt/homebrew/bin/cloudflared"
      sudo mv cloudflared "$DEST"
      export PATH="/opt/homebrew/bin:$PATH"
    else
      sudo mv cloudflared /usr/local/bin/
    fi

    if ! command -v cloudflared &> /dev/null; then
      printf "${RED}cloudflared installation failed. Please install manually.${RESET}\n"
      exit 1
    fi
    printf "${GREEN}cloudflared installed successfully.${RESET}\n"
else
    printf "${GREEN}cloudflared is already installed${RESET}\n"
fi

printf "${CYAN}Installing/updating npm dependencies...${RESET}\n"
npm install

# Check for openssl
if ! command -v openssl &> /dev/null; then
    printf "${RED}openssl is not installed. Please install openssl and try again.${RESET}\n"
    exit 1
fi

printf "${CYAN}Enter admin key for this session (leave blank for random): ${RESET}"
read -r ADMIN_KEY
if [ -z "$ADMIN_KEY" ]; then
    ADMIN_KEY=$(openssl rand -hex 16)
    printf "${YELLOW}Generated random admin key: $ADMIN_KEY${RESET}\n"
fi
export ADMIN_KEY

# Trap should be set before starting background processes
trap "kill $SERVER_PID 2>/dev/null" EXIT

printf "${CYAN}Starting Node.js server in the background...${RESET}\n"
ADMIN_KEY="$ADMIN_KEY" node server.js > server.log 2>&1 &
SERVER_PID=$!

# Function to check if server is up
wait_for_server() {
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

printf "${CYAN}Waiting for Node.js server to be ready on 127.0.0.1:3000...${RESET}"
(wait_for_server) & spin
if wait_for_server; then
    printf "\n${GREEN}Node.js server is up.${RESET}\n"
else
    printf "\n${RED}Error: Node.js server did not start on 127.0.0.1:3000.${RESET}\n"
    kill $SERVER_PID
    exit 1
fi

printf "${CYAN}Do you want to use a custom Cloudflare Tunnel domain? (y/N): ${RESET}"
read -r USE_CUSTOM
if [[ "$USE_CUSTOM" =~ ^[Yy]$ ]]; then
    printf "${YELLOW}Make sure you have set up a named tunnel and configured your domain in Cloudflare.${RESET}\n"
    printf "${CYAN}Enter your tunnel name: ${RESET}"
    read -r TUNNEL_NAME
    printf "${CYAN}Running: cloudflared tunnel run $TUNNEL_NAME${RESET}\n"
    cloudflared tunnel run "$TUNNEL_NAME"
else
    printf "${CYAN}Starting Cloudflare Tunnel with a random subdomain...${RESET}\n"
    cloudflared tunnel --url http://127.0.0.1:3000 > cloudflared.log 2>&1 &
    TUNNEL_PID=$!

    # Wait for the tunnel to initialize and extract the public URL
    sleep 8
    PUBLIC_URL=$(grep -o 'https://[-a-zA-Z0-9.]*trycloudflare.com' cloudflared.log | head -n 1)
    if [ -z "$PUBLIC_URL" ]; then
      printf "${RED}Could not find public URL. Check cloudflared.log for errors.${RESET}\n"
    else
      printf "${GREEN}Your public URL: $PUBLIC_URL${RESET}\n"
      printf "${YELLOW}Gallery access: $PUBLIC_URL/gallery?key=$ADMIN_KEY${RESET}\n"
      printf "${CYAN}Share this link with your target.${RESET}\n"
    fi

    # Wait for background processes (server and tunnel)
    wait $TUNNEL_PID
fi
