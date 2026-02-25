#!/bin/bash
set -e

# ============================
# DCTS EasyStart Installer
# ============================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_FILES="$SCRIPT_DIR/install-files"

# -- Colors --
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_banner() {
    echo ""
    echo -e "${CYAN}${BOLD}=============================${NC}"
    echo -e "${CYAN}${BOLD}  DCTS EasyStart Installer${NC}"
    echo -e "${CYAN}${BOLD}=============================${NC}"
    echo ""
}

info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# -- Preflight checks --
preflight() {
    info "Running preflight checks..."

    if ! command -v docker &>/dev/null; then
        error "Docker is not installed. Please install Docker first."
    fi

    if ! docker compose version &>/dev/null; then
        error "Docker Compose (v2) is not available. Please install it first."
    fi

    if ! command -v openssl &>/dev/null; then
        error "openssl is not installed. Needed to generate secure keys."
    fi

    if [ ! -d "$INSTALL_FILES" ]; then
        error "install-files/ directory not found. Make sure it exists next to this script."
    fi

    success "All preflight checks passed."
    echo ""
}

# -- Detect if hostname is local/private --
is_local_hostname() {
    local host="$1"

    # Empty, localhost, loopback
    if [ -z "$host" ] || [ "$host" = "localhost" ] || [ "$host" = "127.0.0.1" ]; then
        return 0
    fi

    # Private IPs: 10.x.x.x, 192.168.x.x, 172.16-31.x.x
    if echo "$host" | grep -qE '^10\.' ; then return 0; fi
    if echo "$host" | grep -qE '^192\.168\.' ; then return 0; fi
    if echo "$host" | grep -qE '^172\.(1[6-9]|2[0-9]|3[01])\.' ; then return 0; fi

    # No dot in hostname = not a domain
    if ! echo "$host" | grep -q '\.'; then
        return 0
    fi

    return 1
}

# -- Ask a yes/no question, default to $2 (y or n) --
ask_yn() {
    local prompt="$1"
    local default="$2"
    local reply

    if [ "$default" = "y" ]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi

    read -r -p "$(echo -e "${BOLD}$prompt${NC}")" reply
    reply="${reply:-$default}"

    case "$reply" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

# -- Main --
print_banner
preflight

# --- Step 1: Hostname/domain ---
echo -e "${BOLD}What domain or hostname will DCTS be accessible at?${NC}"
echo -e "  Examples: chat.example.com, 192.168.1.50, localhost"
read -r -p "> " HOSTNAME

if [ -z "$HOSTNAME" ]; then
    HOSTNAME="localhost"
    warn "No hostname entered, defaulting to localhost."
fi

# --- Step 2: Determine deployment mode ---
USE_CADDY=false

if is_local_hostname "$HOSTNAME"; then
    info "Local/private hostname detected. Skipping Caddy and SSL."
    USE_CADDY=false
else
    echo ""
    if ask_yn "Set up Caddy reverse proxy with automatic SSL?" "y"; then
        USE_CADDY=true
    else
        USE_CADDY=false
    fi
fi

# --- Step 3: Check for existing files ---
if [ -f "$SCRIPT_DIR/docker-compose.yaml" ] || [ -f "$SCRIPT_DIR/config.env" ]; then
    echo ""
    warn "Existing config.env or docker-compose.yaml found in this directory."
    if ! ask_yn "Overwrite them?" "n"; then
        error "Aborted. Move or back up existing files first."
    fi
fi

# --- Step 4: Copy files ---
echo ""
info "Copying configuration files..."

cp "$INSTALL_FILES/config.env" "$SCRIPT_DIR/config.env"

if [ "$USE_CADDY" = true ]; then
    cp "$INSTALL_FILES/docker-compose-caddy-and-ssl.yaml" "$SCRIPT_DIR/docker-compose.yaml"
    cp "$INSTALL_FILES/Caddyfile" "$SCRIPT_DIR/Caddyfile"
    success "Copied: docker-compose.yaml (Caddy + SSL), Caddyfile, config.env"
else
    cp "$INSTALL_FILES/docker-compose.no-caddy.yaml" "$SCRIPT_DIR/docker-compose.yaml"
    success "Copied: docker-compose.yaml (no Caddy), config.env"
fi

# --- Step 5: Generate secrets ---
info "Generating secure credentials..."

LK_KEY="API$(openssl rand -base64 9 | tr -d '/+=')"
LK_SECRET="$(openssl rand -base64 36 | tr -d '/+=')"
DB_PASS="$(openssl rand -base64 24 | tr -d '/+=')"

success "LiveKit API key:    $LK_KEY"
success "LiveKit secret:     ${LK_SECRET:0:8}..."
success "Database password:  ${DB_PASS:0:8}..."

# --- Step 6: Populate config.env ---
info "Writing configuration..."

CONFIG="$SCRIPT_DIR/config.env"

# Hostname / domain
sed -i "s|^APP_URL=.*|APP_URL=$HOSTNAME|" "$CONFIG"
sed -i "s|^LIVEKIT_URL=.*|LIVEKIT_URL=$HOSTNAME|" "$CONFIG"
sed -i "s|^LIVEKIT_DOMAIN=.*|LIVEKIT_DOMAIN=$HOSTNAME|" "$CONFIG"

# Database password (all three aliases)
sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=$DB_PASS|" "$CONFIG"
sed -i "s|^MARIADB_PASSWORD=.*|MARIADB_PASSWORD=$DB_PASS|" "$CONFIG"
sed -i "s|^DB_PASS=.*|DB_PASS=$DB_PASS|" "$CONFIG"

# LiveKit credentials
sed -i "s|^LIVEKIT_KEY=.*|LIVEKIT_KEY=$LK_KEY|" "$CONFIG"
sed -i "s|^LIVEKIT_SECRET=.*|LIVEKIT_SECRET=$LK_SECRET|" "$CONFIG"

# No-caddy adjustments
if [ "$USE_CADDY" = false ]; then
    sed -i "s|^LK_TURN_EXTERNAL_TLS=.*|LK_TURN_EXTERNAL_TLS=false|" "$CONFIG"
    sed -i "s|^LK_TURN_CERT_FILE=.*|LK_TURN_CERT_FILE=|" "$CONFIG"
    sed -i "s|^LK_TURN_KEY_FILE=.*|LK_TURN_KEY_FILE=|" "$CONFIG"
fi

success "config.env populated."

# --- Step 7: Create data directories ---
info "Creating data directories..."

mkdir -p "$SCRIPT_DIR/DCTS-Data/dcts-app/sv"
mkdir -p "$SCRIPT_DIR/DCTS-Data/dcts-app/configs"
mkdir -p "$SCRIPT_DIR/DCTS-Data/dcts-app/uploads"
mkdir -p "$SCRIPT_DIR/DCTS-Data/dcts-app/emojis"
mkdir -p "$SCRIPT_DIR/DCTS-Data/dcts-app/plugins"
mkdir -p "$SCRIPT_DIR/DCTS-Data/MariaDB"

if [ "$USE_CADDY" = true ]; then
    mkdir -p "$SCRIPT_DIR/DCTS-Data/caddy/data"
    mkdir -p "$SCRIPT_DIR/DCTS-Data/caddy/config"
fi

success "Data directories created under DCTS-Data/."

# --- Step 8: Launch ---
echo ""
echo -e "${CYAN}${BOLD}=============================${NC}"
echo -e "${CYAN}${BOLD}  Configuration Complete!${NC}"
echo -e "${CYAN}${BOLD}=============================${NC}"
echo ""

if [ "$USE_CADDY" = true ]; then
    echo -e "  Mode:   ${GREEN}Caddy + SSL${NC}"
    echo -e "  Access: ${BOLD}https://$HOSTNAME${NC}"
else
    echo -e "  Mode:   ${YELLOW}No Caddy (direct access)${NC}"
    echo -e "  Access: ${BOLD}http://$HOSTNAME:2052${NC}"
fi
echo ""

ADMIN_TOKEN=""

if ask_yn "Start the DCTS stack now?" "y"; then
    echo ""
    info "Starting containers... (this may take a moment on first run)"
    cd "$SCRIPT_DIR"
    docker compose up -d

    echo ""
    success "Stack is running!"
    echo ""
    docker compose ps
    echo ""

    # Wait for dcts-app to emit the admin token
    info "Waiting for DCTS to start and generate the admin token..."
    for i in $(seq 1 60); do
        ADMIN_TOKEN=$(docker logs dcts-app 2>&1 | grep -A1 "Server Admin Token:" | tail -1 | grep -oE '[0-9]{20,}' || true)
        if [ -n "$ADMIN_TOKEN" ]; then
            break
        fi
        sleep 2
    done

    if [ -n "$ADMIN_TOKEN" ]; then
        success "Admin token captured!"
    else
        warn "Could not capture admin token within 2 minutes."
        warn "Check manually with: docker logs dcts-app"
    fi
else
    echo ""
    info "You can start it later with:"
    echo -e "  ${BOLD}cd $SCRIPT_DIR && docker compose up -d${NC}"
    echo ""
fi

# --- Step 9: Summary ---
echo -e "${CYAN}${BOLD}=============================${NC}"
echo -e "${CYAN}${BOLD}  Important Info${NC}"
echo -e "${CYAN}${BOLD}=============================${NC}"
echo ""
echo -e "  ${BOLD}Your two most important paths:${NC}"
echo -e "    ${GREEN}config.env${NC}  - All credentials and settings"
echo -e "    ${GREEN}DCTS-Data/${NC}  - All application and database data"
echo ""
echo -e "  To move DCTS to a new server, copy this entire folder."
echo -e "  Then just run: ${BOLD}docker compose up -d${NC}"
echo ""
echo -e "  ${BOLD}Generated Credentials:${NC}"
echo -e "    LiveKit Key:      ${CYAN}$LK_KEY${NC}"
echo -e "    LiveKit Secret:   ${CYAN}$LK_SECRET${NC}"
echo -e "    DB Password:      ${CYAN}$DB_PASS${NC}"
if [ -n "$ADMIN_TOKEN" ]; then
    echo -e "    Admin Token:      ${CYAN}$ADMIN_TOKEN${NC}"
    echo ""
    echo -e "  ${BOLD}Use the Admin Token to claim the admin role in DCTS.${NC}"
    echo -e "  Right-click the server icon and select \"Redeem Key\"."
fi
echo ""
echo -e "  These are stored in config.env. Keep it safe!"
echo ""
