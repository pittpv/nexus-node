#!/bin/bash

set -e

NEXUS_DIR="$HOME/nexus"
WATCHTOWER_DIR="$HOME/watchtower"

YELLOW='\033[1;33m'
GREEN='\033[1;32m'
RED='\033[1;31m'
NC='\033[0m'

NODE_ID=""
TG_TOKEN=""
TG_CHAT_ID=""

print_menu() {
  show_logo
  echo ""
  echo -e "${YELLOW}========= Nexus Node Menu =========${NC}"
  echo "1) Install Docker (latest)"
  echo "2) Install Nexus Node and Watchtower"
  echo -e "${RED}3) Remove Nexus Node and Watchtower${NC}"
  echo "4) Stop containers (docker compose down)"
  echo "5) Start containers (docker compose up -d)"
  echo -e "${RED}0) Exit${NC}"
  echo -e "${YELLOW}===================================${NC}"
  echo -n "Choose an option: "
}

show_logo() {
    echo -e " "
    echo -e " "
    echo -e "${NC}Welcome to the Nexus Node Setup Script${NC}"
    curl -s https://raw.githubusercontent.com/pittpv/nexus-node/refs/heads/main/other/logo.sh | bash
}

install_docker() {
  echo -e "${GREEN}Installing Docker...${NC}"
  if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
  else
    echo "Docker is already installed."
  fi

  if ! docker compose version &>/dev/null; then
    echo -e "${GREEN}Installing Docker Compose...${NC}"
    sudo curl -L "https://github.com/docker/compose/releases/download/$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r .tag_name)/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
  else
    echo "Docker Compose is already installed."
  fi

  echo -e "${GREEN}Docker and Compose are installed.${NC}"
}

prompt_node_config() {
  echo -n "Enter your NODE_ID: "
  read -r NODE_ID
  while [[ -z "$NODE_ID" ]]; do
    echo -n "NODE_ID cannot be empty. Enter again: "
    read -r NODE_ID
  done

  echo -n "Enter your Telegram Bot Token (TG_TOKEN): "
  read -r TG_TOKEN
  while [[ -z "$TG_TOKEN" ]]; do
    echo -n "TG_TOKEN cannot be empty. Enter again: "
    read -r TG_TOKEN
  done

  echo -n "Enter your Telegram Chat ID (TG_CHAT_ID): "
  read -r TG_CHAT_ID
  while [[ -z "$TG_CHAT_ID" ]]; do
    echo -n "TG_CHAT_ID cannot be empty. Enter again: "
    read -r TG_CHAT_ID
  done

  validate_telegram_config
}

validate_telegram_config() {
  echo -e "${GREEN}Validating Telegram token and chat ID...${NC}"
  local test_message="Nexus Watchtower test message"
  local response
  response=$(curl -s -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
    -d chat_id="$TG_CHAT_ID" \
    -d text="$test_message")

  if echo "$response" | grep -q '"ok":true'; then
    echo -e "${GREEN}Telegram credentials are valid.${NC}"
  else
    echo -e "${RED}❌ Invalid Telegram token or chat ID.${NC}"
    echo "Response: $response"
    echo "Please try again."
    prompt_node_config
  fi
}

install_nexus_node() {
  echo -e "${GREEN}Setting up Nexus Node...${NC}"
  mkdir -p "$NEXUS_DIR"

  # .env file
  cat > "$NEXUS_DIR/.env" <<EOF
NODE_ID=$NODE_ID
TG_TOKEN=$TG_TOKEN
TG_CHAT_ID=$TG_CHAT_ID
EOF

  # docker-compose.yml
  cat > "$NEXUS_DIR/docker-compose.yml" <<EOF
services:
  nexus-cli:
    container_name: nexus
    restart: unless-stopped
    image: nexusxyz/nexus-cli:latest
    init: true
    command: start --node-id \${NODE_ID}
    stdin_open: true
    tty: true
    env_file:
      - .env
    labels:
      - com.centurylinklabs.watchtower.enable=true
EOF

  echo -e "${GREEN}Nexus Node configuration created in $NEXUS_DIR.${NC}"
}

install_watchtower() {
  echo -e "${GREEN}Setting up Watchtower...${NC}"
  mkdir -p "$WATCHTOWER_DIR"

  if [ -f "$WATCHTOWER_DIR/docker-compose.yml" ]; then
    echo -n "Watchtower config already exists. Overwrite it? [y/n]: "
    read -r overwrite
    if [[ "$overwrite" != "y" ]]; then
      echo "Watchtower setup skipped."
      return
    fi
  fi

  cat > "$WATCHTOWER_DIR/docker-compose.yml" <<EOF
services:
  watchtower:
    image: containrrr/watchtower
    container_name: watchtower
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_POLL_INTERVAL=3600
      - WATCHTOWER_NOTIFICATIONS=shoutrrr
      - WATCHTOWER_NOTIFICATION_URL=telegram://$TG_TOKEN@telegram?channels=$TG_CHAT_ID
      - WATCHTOWER_INCLUDE_RESTARTING=true
      - WATCHTOWER_LABEL_ENABLE=true
EOF

  echo -e "${GREEN}Watchtower configuration created in $WATCHTOWER_DIR.${NC}"
}

install_node_and_watchtower() {
  prompt_node_config
  install_nexus_node
  install_watchtower
  echo -e "${GREEN}Setup complete. Use option 5 to start containers.${NC}"
}

remove_node_and_watchtower() {
  echo -e "${YELLOW}Removing Nexus Node and Watchtower...${NC}"
  [ -d "$NEXUS_DIR" ] && (cd "$NEXUS_DIR" && docker compose down -v) || echo "Nexus not found."
  [ -d "$WATCHTOWER_DIR" ] && (cd "$WATCHTOWER_DIR" && docker compose down -v) || echo "Watchtower not found."
  rm -rf "$NEXUS_DIR" "$WATCHTOWER_DIR"
  echo -e "${GREEN}All removed.${NC}"
}

stop_containers() {
  echo -e "${YELLOW}Stopping containers...${NC}"
  [ -f "$NEXUS_DIR/docker-compose.yml" ] && (cd "$NEXUS_DIR" && docker compose down)
  [ -f "$WATCHTOWER_DIR/docker-compose.yml" ] && (cd "$WATCHTOWER_DIR" && docker compose down)
}

start_containers() {
  echo -e "${GREEN}Starting containers...${NC}"
  [ -f "$NEXUS_DIR/docker-compose.yml" ] && (cd "$NEXUS_DIR" && docker compose up -d) || echo "Nexus not installed."
  [ -f "$WATCHTOWER_DIR/docker-compose.yml" ] && (cd "$WATCHTOWER_DIR" && docker compose up -d) || echo "Watchtower not installed."
}

# Main loop
while true; do
  print_menu
  read -r choice
  case $choice in
    1) install_docker ;;
    2) install_node_and_watchtower ;;
    3) remove_node_and_watchtower ;;
    4) stop_containers ;;
    5) start_containers ;;
    0) echo "Exiting..."; exit 0 ;;
    *) echo "Invalid input. Choose between 0 and 5." ;;
  esac
done
