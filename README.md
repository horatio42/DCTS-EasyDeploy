# DCTS EasyDeploy

The easy way to get [DCTS](https://github.com/hackthedev/dcts-shipping) up and running with Docker.

This installer handles everything for you — picks the right configuration, generates secure passwords and API keys, and starts the whole stack with one script.

## Requirements

- A Linux server (or any machine with a terminal)
- [Docker](https://docs.docker.com/get-docker/) installed
- [Docker Compose](https://docs.docker.com/compose/install/) v2 installed (included with Docker Desktop)
- `openssl` (usually pre-installed on Linux/macOS)

## Installation

### 1. Clone this repository

```bash
git clone https://github.com/horatio42/DCTS-EasyDeploy.git
cd DCTS-EasyDeploy
```

### 2. Run the installer

```bash
./thatwaseasy.sh
```

That's it! The script will walk you through everything:

- Ask for your domain name (or use `localhost` for local testing)
- Automatically set up Caddy with SSL if you have a domain, or skip it for local installs
- Generate all the secure passwords and API keys you need
- Create the data folders
- Start everything up
- Give you your admin token so you can claim the admin role

### 3. Open DCTS

Once the installer finishes, open your browser and go to:

- **With a domain:** `https://yourdomain.com`
- **Local install:** `http://localhost:2052`

## After Installation

### Claiming Admin

When the installer finishes, it will show you a **Server Admin Token**. To use it:

1. Open DCTS in your browser
2. Right-click the server icon
3. Click **"Redeem Key"**
4. Paste in the admin token

### Important Files

| Path | What it is |
|------|-----------|
| `config.env` | All your settings, passwords, and API keys |
| `DCTS-Data/` | All your application data, uploads, and database |

**Back these up!** They contain everything you need.

### Moving to a New Server

1. Copy the entire `DCTS-EasyDeploy` folder to the new machine
2. Make sure Docker is installed on the new machine
3. Run:

```bash
cd DCTS-EasyDeploy
docker compose up -d
```

Everything comes back exactly as it was.

### Stopping and Starting

```bash
# Stop everything
docker compose down

# Start everything back up
docker compose up -d

# Check what's running
docker compose ps

# View logs
docker compose logs -f
```

## Need Help?

If you run into any issues, ask **Horatio** on the **DCTS Discord**: [https://discord.gg/AYq8hbRHNR](https://discord.gg/AYq8hbRHNR)

For bugs or feature requests related to DCTS itself, visit the main project: [github.com/hackthedev/dcts-shipping](https://github.com/hackthedev/dcts-shipping)
