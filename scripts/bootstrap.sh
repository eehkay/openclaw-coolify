#!/usr/bin/env bash
set -e

OPENCLAW_STATE="/root/.openclaw"
CONFIG_FILE="$OPENCLAW_STATE/openclaw.json"
WORKSPACE_DIR="/root/openclaw-workspace"

# ----------------------------
# Memory: add swap if missing
# ----------------------------
# Swap creation disabled for Docker containers
# if [ "$(free -m | awk '/Swap/ {print $2}')" -eq 0 ]; then
  #   echo "🧠 No swap detected. Creating 2GB swap..."
  #   fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048
  #   chmod 600 /swapfile
  #   mkswap /swapfile >/dev/null
  #   swapon /swapfile >/dev/null
# fi

mkdir -p "$OPENCLAW_STATE" "$WORKSPACE_DIR"
chmod 700 "$OPENCLAW_STATE"

mkdir -p "$OPENCLAW_STATE/credentials"
mkdir -p "$OPENCLAW_STATE/agents/main/sessions"
chmod 700 "$OPENCLAW_STATE/credentials"

# ----------------------------
# Seed Agent Workspaces
# ----------------------------
seed_agent() {
  local id="$1"
  local name="$2"
  local dir="/root/openclaw-$id"

  if [ "$id" = "main" ]; then
    dir="/root/openclaw-workspace"
  fi

  mkdir -p "$dir"

  # 🔒 NEVER overwrite existing SOUL.md
  if [ -f "$dir/SOUL.md" ]; then
    echo "🧠 SOUL.md already exists for $id — skipping"
    return 0
  fi

  # ✅ MAIN agent gets ORIGINAL repo SOUL.md and BOOTSTRAP.md
  if [ "$id" = "main" ]; then
    if [ -f "./SOUL.md" ] && [ ! -f "$dir/SOUL.md" ]; then
      echo "✨ Copying original SOUL.md to $dir"
      cp "./SOUL.md" "$dir/SOUL.md"
    fi
    if [ -f "./BOOTSTRAP.md" ] && [ ! -f "$dir/BOOTSTRAP.md" ]; then
      echo "🚀 Seeding BOOTSTRAP.md to $dir"
      cp "./BOOTSTRAP.md" "$dir/BOOTSTRAP.md"
    fi
    return 0
  fi

  # fallback for other agents
  cat >"$dir/SOUL.md" <<EOF
# SOUL.md - $name
You are OpenClaw, a helpful and premium AI assistant.
EOF
}

seed_agent "main" "OpenClaw"

# ----------------------------
# Generate Config
# ----------------------------
if [ ! -f "$CONFIG_FILE" ]; then
  echo "🏥 Generating openclaw.json..."
  TOKEN=$(openssl rand -hex 24 2>/dev/null || node -e "console.log(require('crypto').randomBytes(24).toString('hex'))")
  cat >"$CONFIG_FILE" <<EOF
{
  "gateway": {
    "auth": { "mode": "token", "token": "$TOKEN" }
  },
  "agents": {
    "defaults": {
      "workspace": "$WORKSPACE_DIR"
    },
    "list": [
      { "id": "main", "name": "OpenClaw", "workspace": "$WORKSPACE_DIR" }
    ]
  }
}
EOF
fi

# ----------------------------
# Fix any invalid config keys from previous versions
# ----------------------------
if [ -f "$CONFIG_FILE" ]; then
  echo "🔧 Running openclaw doctor --fix..."
  openclaw doctor --fix --yes 2>/dev/null || true
fi

# ----------------------------
# Export state
# ----------------------------
export OPENCLAW_STATE_DIR="$OPENCLAW_STATE"

# ----------------------------
# Sandbox setup
# ----------------------------
[ -f scripts/sandbox-setup.sh ] && bash scripts/sandbox-setup.sh
[ -f scripts/sandbox-browser-setup.sh ] && bash scripts/sandbox-browser-setup.sh

# ----------------------------
# Recovery & Monitoring
# ----------------------------
if [ -f scripts/recover_sandbox.sh ]; then
  echo "🛡️  Deploying Recovery Protocols..."
  cp scripts/recover_sandbox.sh "$WORKSPACE_DIR/"
  cp scripts/monitor_sandbox.sh "$WORKSPACE_DIR/"
  chmod +x "$WORKSPACE_DIR/recover_sandbox.sh" "$WORKSPACE_DIR/monitor_sandbox.sh"
  
  # Run initial recovery
  bash "$WORKSPACE_DIR/recover_sandbox.sh"
  
  # Start background monitor
  nohup bash "$WORKSPACE_DIR/monitor_sandbox.sh" >/dev/null 2>&1 &
fi

# ----------------------------
# Run OpenClaw
# ----------------------------
exec openclaw gateway run
