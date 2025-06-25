# DocPhish

A reusable phishing demonstration tool inspired by CamPhish, featuring:
- Dynamic admin key (set at every run)
- Cloudflare Tunnel integration (random or custom domain)
- Automated setup script
- Simple, extensible Node.js/Express backend

## Quick Start

1. **Clone the repo:**
git clone https://github.com/Neptune-75/DocPhish.git
cd DocPhish

2. **Run the setup script:**
chmod +x setup.sh
./setup.sh

text
- Enter an admin key or press Enter for a random one.
- The server and Cloudflare Tunnel will start automatically.
- If you want a custom domain, follow the prompts.

3. **Access the tool:**
- Use the public URL from cloudflared.
- Gallery: `/gallery?key=YOUR_ADMIN_KEY` (key is shown in your terminal).

## Custom Domain with Cloudflare Tunnel

- [Follow this guide](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/create-tunnel/) to create a named tunnel and route it to your custom domain.
- When prompted in `setup.sh`, enter your tunnel name to use your custom domain.

## Updating

- To update dependencies and system packages, just re-run:
./setup.sh


## Security

- The admin gallery is only accessible with the key you set at startup.
- Never share your admin key or custom domain with unauthorized users.

## License

AANI
