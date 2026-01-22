# t Automation Suite: The Ultimate Usage Guide

## 1. Overview

The t suite is a modular, context-aware DevOps framework designed to automate the lifecycle of dcTrack/Sunbird environments. It bridges the gap between local development and remote server management, handling everything from Java/Node deployments to VM provisioning and Docker orchestration.

**Key Philosophy:**

- **Context-Aware**: t deploy knows what to deploy based on which directory you are in.
- **Self-Healing**: SSH connections automatically fix "Host Key" errors and install missing keys.
- **Interactive**: Uses gum for modern, fuzzy-search menus and safe confirmation dialogs.

## 2. Installation & Setup

### Prerequisites

- **OS**: Linux (Ubuntu/Debian/RHEL/Rocky) or macOS.
- **Dependencies**: sshpass, rsync, sshfs (for remote editing).
- **UI Tool**: gum (The installer attempts to install this automatically).

### One-Time Setup

Run the installer to register aliases (t, td, tf, te) and generate the completion script.

```bash
# 1. Clone/Copy scripts to ~/scripts
# 2. Run the installer
source ~/scripts/tool_install.sh
```

**Registered Aliases:**

- `t`: Main dispatcher.
- `td`: Shortcut for t deploy (Deploy current project).
- `tf`: Shortcut for t find (Search command cheatsheet).
- `te`: Shortcut for t edit (Remote file editor).

### Configuration (.t_config)

Customize your environment in `~/scripts/tool/.t_config`.

- `BASE_IP / DEFAULT_SUBNET`: Defines your network segment (e.g., 192.168.78).
- `LOCAL_IDE_PATH`: Path to your IDE launcher (e.g., IntelliJ) for remote editing.
- `JP_LEGACY_*`: Configuration for JProfiler 12 (used for older Java 17- builds).

## 3. Daily Workflows

### 🚀 Smart Deployment (td)

**Command:** `t deploy <IP>` or `td <IP>`

**Logic:** The tool scans your current working directory to decide what to do.

| Context | Required Fingerprint | Action Performed |
|---------|---------------------|------------------|
| Server | Directory named `server` + contains `./dcTrackApp` | Maven Build → Upload WAR → Restart Tomcat. |
| Client | Path contains `client` + contains `package.json` | NPM Build → Upload `dist/` → Fix Perms. |
| Database | Contains `./.../liquibase/changesets` | Rsync Changesets → Run Remote Migration Script. |

**Example:**

```bash
cd ~/projects/dctrack_app/server
td 105   # Deploys Server to 192.168.78.105
```

### 📝 Remote Editing (te)

**Command:** `t edit <IP> [path]` or `te <IP>`

**Features:**

- **SSHFS Mounting**: Mounts the remote root to `/tmp/t_mnt_<IP>` for seamless editing.
- **History Menu**: If no path is provided, shows a fuzzy-searchable list of recently edited files.
- **IDE Integration**: Opens the file directly in IntelliJ (or Vim/Nano if preferred).

### 🐳 Docker Management

**Command:** `t docker <IP>`

Opens an interactive menu for Docker operations.

1. **Install**: Installs Docker Engine and configures `daemon.json` (Nexus registry, Data Root).
2. **Deploy Env**: Pulls docker-compose configs, injects `env.dev`, and starts the platform.
3. **Deploy Code**: Syncs local artifacts (WARs) into the running container and restarts Tomcat.
4. **Optimize Storage**: Moves `/var/lib/docker` to a larger partition (`/var/oculan`) using bind mounts to prevent root disk saturation.

### 🔍 Log Viewing

**Command:** `t viewlog <IP>` or `t log <IP>`

Fetches a list of relevant logs (Tomcat, Postgres, ActiveMQ) from the remote server.

**Features:**

- **Dynamic Discovery**: Finds the latest PostgreSQL log automatically.
- **Viewer Choice**: Open in lnav (Terminal) or glogg (GUI) via `t setlogviewer`.

## 4. Admin & Infrastructure

### 🛠️ VM Initialization (initvm)

**Command:** `t initvm <IP>`

**Use Case:** Bootstraps a fresh VM "out of the box".

- **Root Access**: Syncs your local "Bridge User" password to the remote root account.
- **SSH Keys**: Installs your public key for password-less login.
- **Postgres Trust**: Whitelists your local IP in `pg_hba.conf`.
- **Tomcat Debug**: Enables JPDA debugging on Port 8000.

### 🕵️ JProfiler Integration

**Command:** `t jprofiler <IP> [off]`

Automatically detects the target Java version and applies the correct strategy.

- **Modern (Java 21+)**: Prints instructions for Client-Side SSH Attach (Zero-config).
- **Legacy (Java 17-)**: Downloads and installs JProfiler 12 Agent, configures `setenv.sh`, and restarts Tomcat.
- **Disable**: Run `t jprofiler <IP> off` to remove the agent and restart.

### 📚 Knowledge Base (tf)

**Command:** `t find [query]` or `tf [query]`

Searches your personal command library (`m3_my_commands.txt`) using fuzzy logic.

- **Smart Search**: "remove file" finds `rm`, "disk usage" finds `df -h`.

## 5. Troubleshooting & Tips

- **"Host Identification Changed"**: Just run `t ssh <IP>`. The tool detects this error and automatically runs `ssh-keygen -R <IP>` to fix it.
- **Missing Dependencies**: If `gum` or `sshpass` is missing, the tool attempts to auto-install them (requires sudo).
- **Custom IP**: You can use a full IP (e.g., `t ssh 10.20.30.40`) or just the last octet (e.g., `t ssh 105`) which expands to `BASE_IP.DEFAULT_SUBNET.105`.
