# 🛰️ Nexus Node Setup with Docker Compose, Watchtower & Telegram Alerts

You can choose **automatic installation via script** or **manual setup**.

---

## ⚡️ Option 1: Automatic Installation (Recommended)

Just run this one-liner in your terminal:

```bash
curl -o nexus3.sh https://raw.githubusercontent.com/pittpv/nexus-node/refs/heads/main/nexus3.sh && chmod +x nexus3.sh && ./nexus3.sh
```

The script will:

* Ask for your `NODE_ID`, Telegram `TG_TOKEN`, and `TG_CHAT_ID`;
* Validate your Telegram credentials;
* Create separate `nexus/` and `watchtower/` directories in your `$HOME`;
* Set up `.env` and `docker-compose.yml` for Nexus;
* Create a `docker-compose.yml` for Watchtower;
* Let you start/stop/remove containers via an interactive menu.

> If Watchtower is already configured, the script will ask before overwriting.

---

## ⚙️ Option 2: Manual Setup

> ⚠️ **Prerequisite:**
> Make sure **Docker** and **Docker Compose** are installed on your system.
> You can follow [this guide to install Docker and dependencies](https://github.com/pittpv/sepolia-auto-install/blob/main/en/Install-Dependecies.md) if you don't have it installed yet.

---

### 📁 Step 1: Create Nexus Directory

```bash
mkdir nexus && cd nexus
```

---

### 🐳 Step 2: Pull the Latest Nexus Image

```bash
docker pull nexusxyz/nexus-cli:latest
```

---

### 🔍 Step 3: Obtain Your Node ID

1. [Open the Nexus web app](https://app.nexus.xyz/nodes) in your browser and Sign in.
2. Click **Add Node** → **Add CLI node**.
3. Copy your **Node ID** – it will look like a long alphanumeric string.

---

### 📄 Step 4: Create `docker-compose.yml` for Nexus

Inside the `nexus/` directory, create:

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

> 🔁 Replace `NODE_ID` with the value you copied in Step 3.

---

### 📁 Step 5: Create Watchtower Directory

```bash
mkdir watchtower && cd watchtower
```

---

### 📄 Step 6: Create `docker-compose.yml` for Watchtower

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

> 🛡️ Replace `TG_TOKEN` and `TG_CHAT_ID` with your **Telegram bot token** and **chat ID**.

---

### 🚀 Step 7: Launch Both Containers

From each folder (`nexus/` and `watchtower/`), run:

```bash
docker compose up -d
```

---

## 🔧 Useful Docker Commands

```bash
# Show running containers
docker ps -a

# Show watchtower logs
docker logs -f watchtower

# View nexus container
docker attach nexus

# Exit from container viewer
Ctrl+P then Ctrl+Q

# Restart a container
docker restart nexus

# Stop and remove containers
docker compose down

# Recreate containers
docker compose up -d
```

---

## ✅ Done!

Your Nexus node is now:

✅ Running via Docker Compose
✅ Automatically updated via Watchtower
✅ Sending update notifications to Telegram

Enjoy smooth and reliable operation! 🚀

---

If you have any questions, feel free to reach out to me on the **Nexus Discord server** by mentioning **@pittpv**.
Here’s the invite link: [https://discord.gg/yCg6b7W7Zd](https://discord.gg/yCg6b7W7Zd)

Official docs: [https://docs.nexus.xyz/layer-1/testnet/testnet-3](https://docs.nexus.xyz/layer-1/testnet/testnet-3)
