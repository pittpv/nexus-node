#!/bin/bash

set -e

BASE_DIR="$HOME/nexus-nodes"
WATCHTOWER_DIR="$HOME/watchtower"

YELLOW='\033[1;33m'
GREEN='\033[1;32m'
RED='\033[1;31m'
BLUE='\033[1;34m'
NC='\033[0m'

NODE_NAME=""
NODE_ID=""
TG_TOKEN=""
TG_CHAT_ID=""

show_logo() {
  echo -e "\n\n${NC}Welcome to the Nexus Multi-Node Setup Script${NC}"
  curl -s https://raw.githubusercontent.com/pittpv/nexus-node/refs/heads/main/other/logo.sh | bash
}

print_menu() {
  show_logo
  echo ""
  echo -e "${NC}========= Nexus Multi-Node Menu =========${NC}"
  echo -e "${YELLOW}1) Check system resources${NC}"
  echo "2) Install Docker (latest)"
  echo -e "${GREEN}3) Install Nexus Node${NC}"
  echo "4) Attach to Nexus Node container (view logs)"
  echo -e "${RED}5) Remove Nexus Node${NC}"
  echo "6) Stop Nexus Node container"
  echo "7) Start Nexus Node container"
  echo "8) Check, create or delete Swap File"
  echo "9) Increase file descriptor limit"
  echo -e "${RED}0) Exit${NC}"
  echo -e "${NC}=========================================${NC}"
  echo -n "Choose an option: "
}

check_docker_installed() {
  if ! command -v docker &>/dev/null; then
    echo -e "${RED}Docker is not installed.${NC}"
    echo -e "${YELLOW}Please run option 2 to install Docker.${NC}"
    return 0
  fi
  return 0
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

install_watchtower_if_needed() {
  IP=$(curl -s https://ifconfig.me || echo "N/A")
  if [ ! -f "$WATCHTOWER_DIR/docker-compose.yml" ]; then
    mkdir -p "$WATCHTOWER_DIR"

    echo -e "${YELLOW}Pulling latest Watchtower image...${NC}"
    docker pull containrrr/watchtower:latest

    # Проверяем TG_TOKEN
    while true; do
      echo -n "Enter your Telegram Bot Token (TG_TOKEN): "
      read -r TG_TOKEN
      if [[ -z "$TG_TOKEN" ]]; then
        echo "TG_TOKEN cannot be empty."
        continue
      fi
      response=$(curl -s -X GET "https://api.telegram.org/bot$TG_TOKEN/getMe")
      if echo "$response" | grep -q '"ok":true'; then
        echo -e "${GREEN}TG_TOKEN is valid.${NC}"
        break
      else
        echo -e "${RED}❌ Invalid TG_TOKEN. Try again.${NC}"
      fi
    done

    # Проверяем TG_CHAT_ID
    while true; do
      echo -n "Enter your Telegram Chat ID (TG_CHAT_ID): "
      read -r TG_CHAT_ID
      if [[ -z "$TG_CHAT_ID" ]]; then
        echo "TG_CHAT_ID cannot be empty."
        continue
      fi
      test_message="Nexus - Watchtower activated on $IP"
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

	# Генерируем URL
	NOTIFY_URL="telegram://$TG_TOKEN@telegram?channels=$TG_CHAT_ID&parseMode=html&title=$IP"

# Записываем всё в .env
	cat > "$WATCHTOWER_DIR/.env" <<EOF
TG_TOKEN=$TG_TOKEN
TG_CHAT_ID=$TG_CHAT_ID
WATCHTOWER_NOTIFICATION_URL=$NOTIFY_URL
EOF

    # Создаём docker-compose.yml
    cat > "$WATCHTOWER_DIR/docker-compose.yml" <<EOF
services:
  watchtower:
    image: containrrr/watchtower:latest
    container_name: watchtower
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    env_file:
      - .env
    environment:
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_POLL_INTERVAL=3600
      - WATCHTOWER_NOTIFICATIONS=shoutrrr
      - WATCHTOWER_NOTIFICATION_URL
      - WATCHTOWER_INCLUDE_RESTARTING=true
      - WATCHTOWER_LABEL_ENABLE=true
EOF

    (cd "$WATCHTOWER_DIR" && docker compose up -d)
    echo -e "${GREEN}Watchtower installed.${NC}"
  fi
}

prompt_node_config() {
  echo "Choose method to get NODE_IDs:"
  echo "1) From file nexus-nodes.txt"
  echo "2) Enter manually"
  read -rp "Enter choice [1 or 2]: " choice

  NODE_IDS=()
  NODE_COUNT=0

  if [[ "$choice" == "1" ]]; then
    if [[ -f "nexus-nodes.txt" ]]; then
      mapfile -t NODE_IDS < nexus-nodes.txt
      NODE_COUNT=${#NODE_IDS[@]}
      echo -e "${GREEN}Using nexus-nodes.txt file with $NODE_COUNT NODE_ID(s).${NC}"
    else
      echo -e "${RED}File nexus-nodes.txt not found. Please create the file with NODE_IDs, one per line.${NC}"
      return 0  # выход в меню
    fi
  elif [[ "$choice" == "2" ]]; then
    echo -n "How many Nexus nodes do you want to install? [default 1]: "
    read -r NODE_COUNT
    [[ ! "$NODE_COUNT" =~ ^[1-9][0-9]*$ ]] && NODE_COUNT=1
  else
    echo -e "${RED}Invalid choice. Returning to menu.${NC}"
    return 0
  fi

  echo -n "Enter number of threads for each node [1-8, default 1]: "
  read -r THREADS
  [[ ! "$THREADS" =~ ^[1-8]$ ]] && THREADS=1

  echo -e "${GREEN}Pulling latest nexusxyz/nexus-cli:latest Docker image...${NC}"
  docker pull nexusxyz/nexus-cli:latest

  for ((n=1; n<=NODE_COUNT; n++)); do
    # Получаем NODE_ID
    if [[ "$choice" == "1" && ${#NODE_IDS[@]} -ge n ]]; then
      NODE_ID="${NODE_IDS[$((n-1))]}"
      echo "Using NODE_ID from nexus-nodes.txt: $NODE_ID"
    else
      echo -n "Enter your NODE_ID: "
      read -r NODE_ID
      while [[ -z "$NODE_ID" ]]; do
        echo -n "NODE_ID cannot be empty. Enter again: "
        read -r NODE_ID
      done
    fi

    # Формируем имя ноды на основе NODE_ID
    SAFE_NODE_ID=$(echo "$NODE_ID" | tr -c 'a-zA-Z0-9_.-' '-')
    SAFE_NODE_ID=$(echo "$SAFE_NODE_ID" | sed -E 's/^-+//; s/-+$//; s/-+/-/g')
    NODE_NAME="nexus-$SAFE_NODE_ID"
    NODE_DIR="$BASE_DIR/$NODE_NAME"

    # Если папка уже есть — предупреждение и пропуск или можно предложить другое имя
    if [[ -d "$NODE_DIR" ]]; then
      echo -e "${YELLOW}Warning: directory $NODE_DIR already exists. Skipping this node to avoid conflict.${NC}"
      continue
    fi

    mkdir -p "$NODE_DIR"
    echo -e "\nConfiguring $NODE_NAME"

    cat > "$NODE_DIR/.env" <<EOF
NODE_ID=$NODE_ID
MAX_THREADS=$THREADS
EOF

    cat > "$NODE_DIR/docker-compose.yml" <<EOF
services:
  nexus-node:
    container_name: $NODE_NAME
    restart: unless-stopped
    image: nexusxyz/nexus-cli:latest
    init: true
    command: start --node-id \${NODE_ID} --max-threads \${MAX_THREADS}
    stdin_open: true
    tty: true
    env_file:
      - .env
    labels:
      - com.centurylinklabs.watchtower.enable=true
EOF

    (cd "$NODE_DIR" && docker compose up -d)
    echo -e "${GREEN}Nexus node '$NODE_NAME' installed and running.${NC}"
  done
}

install_nexus_node() {
  check_docker_installed || return
  install_watchtower_if_needed
  prompt_node_config
}

select_node() {
  nodes=($(ls "$BASE_DIR" 2>/dev/null))
  if [ ${#nodes[@]} -eq 0 ]; then
    echo -e "${RED}❌ No Nexus nodes found.${NC}"
    echo ""
    return 1
  fi

  echo -e "\n${BLUE}Select a Nexus Node:${NC}"
  for i in "${!nodes[@]}"; do
    node_name="${nodes[$i]}"
    container_status=$(docker ps -a --format '{{.Names}}' | grep -w "$node_name" &>/dev/null && echo "✅" || echo "❌")
    echo -e "  $((i+1))) ${GREEN}${node_name}${NC} $container_status"
  done
  echo -e "  $(( ${#nodes[@]} + 1 ))) ${YELLOW}All nodes${NC}"
  echo -e "  0) ${YELLOW}Return to main menu${NC}"

  while true; do
    echo -ne "\nEnter your choice (number): "
    read -r choice

    if [[ "$choice" =~ ^[0-9]+$ ]]; then
      if [ "$choice" -eq 0 ]; then
        return 1
      elif [ "$choice" -le ${#nodes[@]} ]; then
        NODE_NAME="${nodes[$((choice-1))]}"
        return 0
      elif [ "$choice" -eq $(( ${#nodes[@]} + 1 )) ]; then
        NODE_NAME="ALL"
        return 0
      fi
    fi
    echo -e "${RED}Invalid choice. Please enter a number between 0 and $((${#nodes[@]} + 1)).${NC}"
  done
}


remove_node() {
  if ! select_node; then
    return  # Возврат в меню при выборе 0 или если нет нод
  fi

  if [ "$NODE_NAME" = "ALL" ]; then
    echo -e "${YELLOW}Are you sure you want to remove ALL nodes? [y/N]: ${NC}"
    read -r confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
      echo -e "${YELLOW}Operation canceled.${NC}"
      return
    fi

    for dir in "$BASE_DIR"/*; do
      [ -d "$dir" ] || continue
      (cd "$dir" && docker compose down -v)
      rm -rf "$dir"
      echo -e "${GREEN}Removed $(basename "$dir")${NC}"
    done

    if [ -d "$BASE_DIR" ] && [ -z "$(ls -A "$BASE_DIR")" ]; then
      rm -rf "$BASE_DIR"
      echo -e "${GREEN}Removed empty base directory '$BASE_DIR'${NC}"
    fi
  else
    NODE_DIR="$BASE_DIR/$NODE_NAME"
    (cd "$NODE_DIR" && docker compose down -v)
    rm -rf "$NODE_DIR"
    echo -e "${GREEN}Node '$NODE_NAME' removed.${NC}"
  fi

  # Запрос подтверждения удаления Watchtower
  if [ -d "$WATCHTOWER_DIR" ]; then
    echo -ne "${YELLOW}Do you also want to remove Watchtower? [y/N]: ${NC}"
    read -r confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
      (cd "$WATCHTOWER_DIR" && docker compose down -v)
      rm -rf "$WATCHTOWER_DIR"
      echo -e "${GREEN}Watchtower removed.${NC}"
    else
      echo -e "${YELLOW}Watchtower was not removed.${NC}"
    fi
  fi
}

stop_containers() {
  if ! select_node; then
    return  # Возврат в меню при выборе 0 или если нет нод
  fi

  if [ "$NODE_NAME" = "ALL" ]; then
    echo -e "${YELLOW}Stopping ALL nodes...${NC}"
    for dir in "$BASE_DIR"/*; do
      [ -d "$dir" ] || continue
      (cd "$dir" && docker compose down)
      echo -e "${GREEN}Stopped $(basename "$dir")${NC}"
    done
  else
    (cd "$BASE_DIR/$NODE_NAME" && docker compose down)
    echo -e "${GREEN}Node '$NODE_NAME' stopped.${NC}"
  fi
}

start_containers() {
  if ! select_node; then
    return  # Возврат в меню при выборе 0 или если нет нод
  fi

  if [ "$NODE_NAME" = "ALL" ]; then
    echo -e "${YELLOW}Starting ALL nodes...${NC}"
    for dir in "$BASE_DIR"/*; do
      [ -d "$dir" ] || continue
      (cd "$dir" && docker compose up -d)
      echo -e "${GREEN}Started $(basename "$dir")${NC}"
    done
  else
    (cd "$BASE_DIR/$NODE_NAME" && docker compose up -d)
    echo -e "${GREEN}Node '$NODE_NAME' started.${NC}"
  fi
}

attach_nexus_container() {
    echo -e "${GREEN}📋 Attaching to Nexus containers using tmux (4 per session)...${NC}"

    if ! command -v tmux &> /dev/null; then
        echo -e "${RED}❌ tmux is not installed. Please install it first.${NC}"
        return 0
    fi

    containers=($(docker ps --format "{{.Names}}" | grep "nexus" | sort))
    total=${#containers[@]}

    if [ $total -eq 0 ]; then
        echo -e "${RED}❌ No running Nexus containers found.${NC}"
        return
    fi

    echo -e "${GREEN}🔍 Found $total Nexus container(s).${NC}"

    max_per_session=4
    session_count=$(( (total + max_per_session - 1) / max_per_session ))

    echo -e "${YELLOW}🧭 Will create $session_count tmux session(s).${NC}"
    echo
    echo -e "${GREEN}✅ Keyboard navigation inside tmux:${NC}"
    echo -e "   Ctrl+b then o — next pane"
    echo -e "   Ctrl+b then w — list windows"
    echo -e "   Ctrl+b then d — detach session"
    echo
    echo -e "${YELLOW}⏳ Starting in 5 seconds... Press Ctrl+C to cancel.${NC}"
    sleep 5

    session_ids=()
    container_index=1

    for ((s=0; s<session_count; s++)); do
        session_name="nexus_attach_$((s+1))"
        session_ids+=("$session_name")

        # Если сессия существует — убиваем ее для чистоты
        if tmux has-session -t "$session_name" 2>/dev/null; then
            echo -e "${YELLOW}🧹 Killing existing tmux session '$session_name'...${NC}"
            tmux kill-session -t "$session_name"
            sleep 1
        fi

        echo -e "🛠 Creating tmux session $session_name..."

        start=$((s * max_per_session))
        group=("${containers[@]:$start:$max_per_session}")

        # Создаем сессию с первым контейнером
        tmux new-session -d -s "$session_name" -n "[${container_index}] ${group[0]}" "docker attach ${group[0]}"
        ((container_index++))

        # Для остальных контейнеров создаем горизонтальные панели
        for ((i=1; i<${#group[@]}; i++)); do
            tmux split-window -h -t "$session_name"
            # переключаемся в новую панель и запускаем attach
            # при split-window tmux по умолчанию фокусирует новую панель, используем это:
            tmux send-keys -t "$session_name" "clear; echo \"Container [${container_index}] ${group[$i]}\"; docker attach ${group[$i]}" C-m
            # проставим заголовок окна (панель не имеет заголовка, поэтому выводим в строке)
            ((container_index++))
        done

        # Организуем горизонтальное расположение (переключаем на tiled layout для горизонтального деления)
        tmux select-layout -t "$session_name" tiled
    done

    echo
    echo -e "${GREEN}🚀 All tmux sessions are ready.${NC}"
    echo -e "Use ${BLUE}tmux attach -t session_name${NC} to attach:"
    for sid in "${session_ids[@]}"; do
        echo -e "  👉  ${BLUE}tmux attach -t $sid${NC}"
    done

    echo
    echo -e "${GREEN}ℹ️ Attaching to first tmux session: ${BLUE}${session_ids[0]}${NC}"
    sleep 2

    tmux attach -t "${session_ids[0]}"
}

create_swap() {
  echo ""

  # Проверка на активный swap-файл
  if swapon --show | grep -q '^/swapfile'; then
    SWAP_ACTIVE=true
    SWAP_SIZE=$(swapon --show --bytes | awk '/\/swapfile/ { printf "%.0f", $3 / 1024 / 1024 }')
    echo -e "${YELLOW}Active swap file found: /swapfile (${SWAP_SIZE} MB)${NC}"
  else
    SWAP_ACTIVE=false
    echo -e "${YELLOW}No active swap file found.${NC}"

    # Проверка на существование неактивного файла
    if [ -f /swapfile ]; then
      SWAP_INACTIVE_SIZE=$(ls -lh /swapfile | awk '{print $5}')
      echo -e "${YELLOW}Inactive swap file exists at /swapfile (${SWAP_INACTIVE_SIZE}).${NC}"

      echo -n "Do you want to activate it now? [y/N]: "
      read -r activate_choice
      if [[ "$activate_choice" =~ ^[Yy]$ ]]; then
        sudo mkswap /swapfile
        sudo swapon /swapfile
        echo -e "${GREEN}Swap file activated.${NC}"

        if grep -i -q microsoft /proc/version; then
          # WSL
          echo -n "Enable swap activation at WSL startup via /etc/wsl.conf? [y/N]: "
          read -r wsl_startup
          if [[ "$wsl_startup" =~ ^[Yy]$ ]]; then
            sudo mkdir -p /etc
            if ! grep -q '^\[boot\]' /etc/wsl.conf 2>/dev/null; then
              echo -e "\n[boot]" | sudo tee -a /etc/wsl.conf > /dev/null
            fi
            if ! grep -q 'swapon /swapfile' /etc/wsl.conf 2>/dev/null; then
              echo 'command = "swapon /swapfile"' | sudo tee -a /etc/wsl.conf > /dev/null
              echo -e "${GREEN}Activation command added to /etc/wsl.conf.${NC}"
            else
              echo -e "${YELLOW}Activation command already present in /etc/wsl.conf.${NC}"
            fi
            echo " "
            echo -e "${NC}To apply changes:${NC}"
            echo -e "${YELLOW}1. Exit script (option 0)"
            echo -e "2. Run: ${GREEN}wsl --shutdown${YELLOW} in PowerShell or CMD"
            echo -e "3. Restart WSL${NC}"
            echo -e "${YELLOW}Returning to menu in 10 seconds...${NC}"
            sleep 10
            return
          fi
        else
          # Серверная Ubuntu
          if ! grep -q '/swapfile' /etc/fstab; then
            echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab > /dev/null
            echo -e "${GREEN}Added swap activation to /etc/fstab.${NC}"
          else
            echo -e "${YELLOW}Swap already listed in /etc/fstab.${NC}"
          fi
        fi
        return
      else
        echo -n "Do you want to remove the inactive swap file? [y/N]: "
        read -r remove_choice
        if [[ "$remove_choice" =~ ^[Yy]$ ]]; then
          sudo rm -f /swapfile
          sudo sed -i '/\/swapfile/d' /etc/fstab
          echo -e "${GREEN}Inactive swap file removed.${NC}"
        else
          echo -e "${YELLOW}Swap file was not removed.${NC}"
        fi
        return
      fi
    fi
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
    1) SWAP_SIZE_MB=8192 ;;
    2) SWAP_SIZE_MB=16384 ;;
    3) SWAP_SIZE_MB=32768 ;;
    4)
      # Определяем активный swap-файл (если есть)
      SWAP_FILE=$(swapon --show --noheadings --raw | awk '$1 ~ /^\// {print $1}' | head -n1)

      if [ -z "$SWAP_FILE" ]; then
        echo -e "${RED}❌ No active swap file found.${NC}"
        return
      fi

      echo -e "${YELLOW}Detected active swap file: ${SWAP_FILE}${NC}"

      # Попытка отключить
      echo -e "${YELLOW}Deactivating swap file...${NC}"
      if ! sudo swapoff "$SWAP_FILE"; then
        echo -e "${RED}❌ Failed to deactivate swap. It might be system-managed or locked.${NC}"
        return
      fi

      # Проверка, что это обычный файл, и он существует
      if [ -f "$SWAP_FILE" ] && stat -c %F "$SWAP_FILE" | grep -q 'regular file'; then
        echo -e "${YELLOW}Removing swap file...${NC}"
        sudo rm -f "$SWAP_FILE"

        # Удаление из /etc/fstab
        if grep -q "$SWAP_FILE" /etc/fstab 2>/dev/null; then
          sudo sed -i "\|$SWAP_FILE|d" /etc/fstab
          echo -e "${GREEN}Removed swap entry from /etc/fstab.${NC}"
        fi

        # Если WSL — удаляем из /etc/wsl.conf
        if grep -qi microsoft /proc/version; then
          if grep -q "swapon $SWAP_FILE" /etc/wsl.conf 2>/dev/null; then
            sudo sed -i "\|swapon $SWAP_FILE|d" /etc/wsl.conf
            echo -e "${GREEN}Removed swap activation from /etc/wsl.conf.${NC}"
          fi
        fi

        echo -e "${GREEN}Swap file ${SWAP_FILE} removed successfully.${NC}"
      else
        echo -e "${RED}❌ $SWAP_FILE is not a regular file or does not exist. Possibly system-managed swap.${NC}"
        echo -e "${YELLOW}Can't delete swap.${NC}"
      fi

      return
      ;;
    0) return ;;
    *) echo -e "${RED}Invalid option. Returning to menu.${NC}"; return ;;
  esac

  echo -e "${GREEN}Creating ${SWAP_SIZE_MB}MB swap file...${NC}"
  sudo dd if=/dev/zero of=/swapfile bs=1M count=$SWAP_SIZE_MB status=progress
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile

  if grep -i -q microsoft /proc/version; then
    # WSL
    echo -e "${YELLOW}Running on WSL. Add swapon to /etc/wsl.conf manually if needed.${NC}"
  else
    # Серверная Ubuntu
    if ! grep -q '/swapfile' /etc/fstab; then
      echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab > /dev/null
      echo -e "${GREEN}Swap entry added to /etc/fstab.${NC}"
    fi
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

check_system_resources() {
    # Configuration automatique des ressources (thanks for function to @leznoxx (discord))
    TOTAL_RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
    TOTAL_CPU_CORES=$(nproc)
    AVAILABLE_RAM_GB=$((TOTAL_RAM_GB - 2))  # Ресервируем 2GB для системы
    AVAILABLE_CPU_CORES=$((TOTAL_CPU_CORES - 1))  # Ресервируем 1 ядро для системы

    # Оптимальное количество нод
    MAX_NODES=$(( (AVAILABLE_RAM_GB / 4) < (AVAILABLE_CPU_CORES / 2) ? (AVAILABLE_RAM_GB / 4) : (AVAILABLE_CPU_CORES / 2) ))

    # Ограничиваем между 1 и 8 нодами (максимум 8 вместо 10)
    MAX_NODES=$(( MAX_NODES < 1 ? 1 : (MAX_NODES > 8 ? 8 : MAX_NODES) ))

    # CPUs на ноду (округление до 1 знака)
    CPUS_PER_NODE=$(awk -v avail="$AVAILABLE_CPU_CORES" -v max="$MAX_NODES" 'BEGIN{printf "%.1f", avail/max}')

    echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║          System Resources & Recommedation          ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}💻 CPU Information:${NC}"
    echo "  Model: $(lscpu | grep 'Model name' | sed 's/Model name: *//')"
    echo "  Total cores: ${TOTAL_CPU_CORES}"
    echo "  Available for node: ${AVAILABLE_CPU_CORES}"
    echo ""
    echo -e "${GREEN}🧠 Memory Information:${NC}"
    echo "  Total RAM: ${TOTAL_RAM_GB}GB"
    echo "  Available RAM: ${AVAILABLE_RAM_GB}GB"
    echo "  Free RAM: $(free -h | awk '/^Mem:/{print $7}')"
    echo ""
    echo -e "${GREEN}💾 Storage Information:${NC}"
    if grep -q "WSL" /proc/version 2>/dev/null; then
        df -h /mnt/c | tail -n 1 | awk '{print "  Windows C: drive: " $2 " total, " $4 " available (" $5 " used)"}'
    else
        df -h / | tail -n 1 | awk '{print "  Root partition: " $2 " total, " $4 " available (" $5 " used)"}'
    fi
    echo ""
    echo -e "${GREEN}🔄 Swap Information:${NC}"
    if swapon --show | grep -q '/'; then
        swapon --show --bytes | awk 'NR>1 { printf "  Swap file: %.1fGB\n", $3 / 1024 / 1024 / 1024 }'
    else
        echo "  No swap file configured"
    fi
    echo ""
    echo -e "${GREEN}🐳 Docker Status:${NC}"
    if command -v docker &>/dev/null; then
        DOCKER_VERSION=$(docker --version | awk '{print $3}' | tr -d ',')
        echo "  Docker is installed (version: $DOCKER_VERSION)"
    else
        echo "  Docker is not installed (you can install it using option 2)"
    fi
    echo ""
    echo -e "${GREEN}📈 Optimal Configuration:${NC}"
    echo "  Recommended number of nodes: ${MAX_NODES}"
    echo "  CPU per node: ${CPUS_PER_NODE} cores"
    echo "  RAM per node: ~4GB"

    # Преобразуем CPUS_PER_NODE в целое число (отбрасываем дробную часть)
    INT_CPUS_PER_NODE=${CPUS_PER_NODE%.*}
    echo "  Total resources used: $((MAX_NODES * 4))GB RAM, $((MAX_NODES * INT_CPUS_PER_NODE)) CPU cores"
    echo ""
}

# Main loop
while true; do
  print_menu
  read -r choice
  case $choice in
    1) check_system_resources ;;
    2) install_docker ;;
    3) install_nexus_node ;;
    4) attach_nexus_container ;;
    5) remove_node ;;
    6) stop_containers ;;
    7) start_containers ;;
    8) create_swap ;;
    9) increase_ulimit ;;
    0) echo "Exiting..."; exit 0 ;;
    *) echo "Invalid input. Choose between 0 and 9." ;;
  esac
  echo ""
  echo -e "${YELLOW}Press Enter to continue...${NC}"
  read -r
  clear
done
