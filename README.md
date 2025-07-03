# 🛰️ Nexus Node Setup with Docker Compose, Watchtower & Telegram Alerts

You can choose **automatic installation via script** or **manual setup**.

---

## ⚡️ Option 1: Automatic Installation (Recommended)

Just run this one-liner in your terminal (first install or update):

```bash
curl -o nexus3.sh https://raw.githubusercontent.com/pittpv/nexus-node/refs/heads/main/nexus3.sh && chmod +x nexus3.sh && ./nexus3.sh
```

For future runs:

```bash
cd $HOME && ./nexus3.sh
```

The script will:

* Ask for your `NODE_ID`, Telegram `TG_TOKEN`, and `TG_CHAT_ID`;
* Validate your Telegram credentials;
* Create separate `nexus/` and `watchtower/` directories in your `$HOME`;
* Set up `.env` and `docker-compose.yml` for Nexus;
* Create a `docker-compose.yml` for Watchtower;
* Let you start/stop/remove containers via an interactive menu.

> If Watchtower is already configured, the script will ask before overwriting.

## 📌 Latest Updates 03-07-2025  
- Added a Docker installation check before setting up the node (for users who are unsure whether Docker is installed on their system).  
- Improved the swap file creation and removal function:  
  - If swap file activation is not configured in the system (**relevant for WSL**), the swap file will **not remain active after rebooting the PC or restarting WSL**. The script will detect this (if you run **Option 7** again after a reboot) and **prompt you to configure swap file activation**.  

<details>
<summary>📅 Version History</summary>

### 02-07-2025  
- Added the function of creating and deleting a swap file. 
  - You can create a file of 8, 16, 32 GB.
  - It will show if the file already exists and its size.
- Added the function of increasing ulimit (file descriptor limit)
  - Increases for the current session to a maximum value of 65535
  - Shows the previous limit

### 01-07-2025  
**Improvements:**
- After exiting the container view, the terminal is cleared and returns to the menu.
- When deleting a node, there is an additional prompt to delete Watchtower (can be skipped if it's used by other containers).
- Watchtower container is removed from Stop/Start—the command now only applies to the node container.

### 30-06-2025  
- Added a function to view the node container
- Minor improvements

</details>

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

## 🛠️ Troubleshooting

### 1. `permission denied while trying to connect to the Docker daemon socket` on WSL

**Cause:** Your user is not part of the `docker` group.

**Solution:**
Run the following command and restart the terminal (WSL):

```bash
sudo usermod -aG docker $USER
```

---

### 2. Nexus container keeps restarting

**Cause:** Not enough RAM available. Nexus requires a lot of memory to run reliably — even 30 GB may be insufficient.

**Solution:**
* Run the node on a machine with more available memory.
* Partial workaround:
  * Create a swap file
  * Increase `ulimit` limits

You can do both using **option 7** and **option 8** in the script.

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

