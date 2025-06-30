# 🛰️ Nexus Node Setup with Docker Compose, Watchtower & Telegram Alerts

> ⚠️ **Prerequisite:**
> Make sure you have **Docker** and **Docker Compose** installed on your system.
> You can install Docker from the official website or using your package manager.


## 📁 Step 1: Create Nexus Directory

```bash
mkdir nexus && cd nexus
```

## 🐳 Step 2: Pull the Latest Nexus Image

```bash
docker pull nexusxyz/nexus-cli:latest
```

## 📄 Step 3: Create `docker-compose.yml` for Nexus

Inside the `nexus/` directory, create the following file:

### `docker-compose.yml`

```yaml
services:
  nexus-cli:
    container_name: nexus
    restart: unless-stopped
    image: nexusxyz/nexus-cli:latest
    init: true
    command: start --node-id NODE_ID
    stdin_open: true
    tty: true
    labels:
      - com.centurylinklabs.watchtower.enable=true
```

> 🔁 Replace `NODE_ID` with your actual node identifier.

---

## 📁 Step 4: Create Watchtower Directory

```bash
mkdir ../watchtower && cd ../watchtower
```

## 📄 Step 5: Create `docker-compose.yml` for Watchtower

Inside the `watchtower/` directory, create:

### `docker-compose.yml`

```yaml
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
      - WATCHTOWER_NOTIFICATION_URL=telegram://TG_TOKEN@telegram?channels=TG_CHAT_ID
      - WATCHTOWER_INCLUDE_RESTARTING=true
      - WATCHTOWER_LABEL_ENABLE=true
```

> 🛡️ Replace `TG_TOKEN` and `TG_CHAT_ID` with your **Telegram bot token** and **chat ID** respectively.

---

## 🚀 Step 6: Launch Both Containers

From each folder (`nexus/` and `watchtower/`), run:

```bash
docker compose up -d
```

---

## 🔧 Useful Docker Commands

```bash
# View running containers
docker ps -a

# View container
docker attach nexus

# Exit from viewer
Ctrl+P then Ctrl+Q
You wıll see response `read escape sequence`

# Restart a container
docker restart nexus

# Stop and remove containers
docker compose down

# Rebuild containers
docker compose up -d
```

---

## ✅ Done!

Your Nexus node is now:

* Running via Docker Compose
* Automatically updated with Watchtower
* Sending update notifications to Telegram

Stay synced and updated effortlessly 🚀
