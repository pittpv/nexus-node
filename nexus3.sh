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
  echo -e "${NC}========= Nexus Node Menu =========${NC}"
  echo "1) Install Docker (latest)"
  echo "2) Install Nexus Node and Watchtower"
  echo "3) Attach to Nexus container (view logs)"
  echo -e "${RED}4) Remove Nexus Node${NC}"
  echo "5) Stop node container (docker compose down)"
  echo "6) Start node container (docker compose up -d)"
  echo "7) Create or delete Swap File (if you have low RAM)"
  echo "8) Increase file descriptor limit (for current session)"
  echo -e "${RED}0) Exit${NC}"
  echo -e "${NC}===================================${NC}"
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

  while true; do
    echo -n "Enter your Telegram Bot Token (TG_TOKEN): "
    read -r TG_TOKEN
    if [[ -z "$TG_TOKEN" ]]; then
      echo "TG_TOKEN cannot be empty."
      continue
    fi

    # Check token with dummy chat_id
    response=$(curl -s -X GET "https://api.telegram.org/bot$TG_TOKEN/getMe")
    if echo "$response" | grep -q '"ok":true'; then
      echo -e "${GREEN}TG_TOKEN is valid.${NC}"
      break
    else
      echo -e "${RED}❌ Invalid TG_TOKEN. Try again.${NC}"
    fi
  done

  while true; do
    echo -n "Enter your Telegram Chat ID (TG_CHAT_ID): "
    read -r TG_CHAT_ID
    if [[ -z "$TG_CHAT_ID" ]]; then
      echo "TG_CHAT_ID cannot be empty."
      continue
    fi

    # Try sending test message
    test_message="Nexus - Watchtower connected"
    response=$(curl -s -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
      -d chat_id="$TG_CHAT_ID" \
      -d text="$test_message")

    if echo "$response" | grep -q '"ok":true'; then
      echo -e "${GREEN}TG_CHAT_ID is valid.${NC}"
      break
    else
      echo -e "${RED}❌ Invalid TG_CHAT_ID. Try again.${NC}"
    fi
  done
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

  echo -e "${GREEN}Starting Nexus and Watchtower containers...${NC}"
  if [ -f "$NEXUS_DIR/docker-compose.yml" ]; then
    (cd "$NEXUS_DIR" && docker compose up -d)
  else
    echo "Nexus docker-compose.yml not found, cannot start Nexus container."
  fi

  if [ -f "$WATCHTOWER_DIR/docker-compose.yml" ]; then
    (cd "$WATCHTOWER_DIR" && docker compose up -d)
  else
    echo "Watchtower docker-compose.yml not found, cannot start Watchtower container."
  fi

  echo -e "${GREEN}Setup and start complete.${NC}"
}

remove_node() {
  echo -e "${YELLOW}Removing Nexus Node...${NC}"
  if [ -d "$NEXUS_DIR" ]; then
    (cd "$NEXUS_DIR" && docker compose down -v)
    rm -rf "$NEXUS_DIR"
    echo -e "${GREEN}Nexus Node removed.${NC}"
  else
    echo "Nexus Node not found."
  fi

  # Запрос подтверждения удаления Watchtower
  if [ -d "$WATCHTOWER_DIR" ]; then
    echo -n "Do you also want to remove Watchtower? [y/N]: "
    read -r confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
      (cd "$WATCHTOWER_DIR" && docker compose down -v)
      rm -rf "$WATCHTOWER_DIR"
      echo -e "${GREEN}Watchtower removed.${NC}"
    else
      echo "Watchtower was not removed."
    fi
  fi
}

stop_containers() {
  echo -e "${YELLOW}Stopping container...${NC}"
  [ -f "$NEXUS_DIR/docker-compose.yml" ] && (cd "$NEXUS_DIR" && docker compose down)
}

start_containers() {
  echo -e "${GREEN}Starting container...${NC}"
  [ -f "$NEXUS_DIR/docker-compose.yml" ] && (cd "$NEXUS_DIR" && docker compose up -d) || echo "Nexus not installed."
}

attach_nexus_container() {
  echo -e "${YELLOW}You are about to attach to the 'nexus' container.${NC}"
  echo "To exit the container view, press Ctrl+P then Ctrl+Q."
  echo "Starting in 7 seconds..."
  sleep 7

  set +e
  docker attach nexus
  set -e

  clear
  echo -e "${GREEN}Returned from container. Back to menu.${NC}"
}

create_swap() {
  echo ""

  # Проверка на существующий swap-файл
  if swapon --show | grep -q '^/swapfile'; then
    SWAP_ACTIVE=true
    SWAP_SIZE=$(swapon --show --bytes | awk '/\/swapfile/ { printf "%.0f", $3 / 1024 / 1024 }')
    echo -e "${YELLOW}Active swap file found: /swapfile (${SWAP_SIZE} MB)${NC}"
  else
    SWAP_ACTIVE=false
    echo -e "${YELLOW}No active swap file found.${NC}"
  fi

  echo -e "${NC}---------- Swap File Menu ----------"
  echo "1) Create 8GB Swap File"
  echo "2) Create 16GB Swap File"
  echo "3) Create 32GB Swap File"
  echo "4) Remove existing Swap File"
  echo -e "${RED}0) Back to main menu${NC}"
  echo -e "${NC}------------------------------------"
  echo -n "Choose an option: "
  read -r swap_choice

  case $swap_choice in
    1)
      SWAP_SIZE_MB=8192
      ;;
    2)
      SWAP_SIZE_MB=16384
      ;;
    3)
      SWAP_SIZE_MB=32768
      ;;
    4)
      if [ "$SWAP_ACTIVE" = true ]; then
        sudo swapoff /swapfile && sudo rm -f /swapfile
        sudo sed -i '/\/swapfile none swap sw 0 0/d' /etc/fstab
        echo -e "${GREEN}Swap file removed successfully.${NC}"
      else
        echo -e "${RED}No active swap file found or removal failed.${NC}"
      fi
      return
      ;;
    0)
      return
      ;;
    *)
      echo -e "${RED}Invalid option. Returning to menu.${NC}"
      return
      ;;
  esac

  echo -e "${GREEN}Creating ${SWAP_SIZE_MB}MB swap file...${NC}"
  sudo dd if=/dev/zero of=/swapfile bs=1M count=$SWAP_SIZE_MB status=progress
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile

  if ! grep -q '/swapfile none swap sw 0 0' /etc/fstab; then
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab > /dev/null
  fi

  echo -e "${GREEN}Swap file of size ${SWAP_SIZE_MB}MB created and activated.${NC}"
}

increase_ulimit() {
  echo -e "${YELLOW}Increasing file descriptor limit for current session...${NC}"
  OLD_LIMIT=$(ulimit -n)
  echo -e "Current limit: ${GREEN}${OLD_LIMIT}${NC}"

  # Попытка установить 65535 (или максимально допустимое значение)
  ulimit -n 65535 2>/dev/null

  NEW_LIMIT=$(ulimit -n)
  echo -e "New limit: ${GREEN}${NEW_LIMIT}${NC}"
}

# Main loop
while true; do
  print_menu
  read -r choice
  case $choice in
    1) install_docker ;;
    2) install_node_and_watchtower ;;
    3) attach_nexus_container ;;
    4) remove_node ;;
    5) stop_containers ;;
    6) start_containers ;;
    7) create_swap ;;
    8) increase_ulimit ;;
    0) echo "Exiting..."; exit 0 ;;
    *) echo "Invalid input. Choose between 0 and 6." ;;
  esac

done
