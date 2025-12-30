# Custom Automation Tool (`t`)

A modular shell script suite for automating Java WAR deployments, Node.js Client builds, Database migrations, and SSH key management.

## 🚀 Features

* **Context-Aware Deployment:** Automatically detects if you are in the **Server**, **Client**, or **Database** repository and triggers the correct workflow.
* **System Updates:** Transfers and executes maintenance scripts (`dnfupdate.sh`) on remote hosts.
* **Smart SSH:** Auto-detects missing keys, handles `ssh-copy-id`, and auto-fixes "Host Identification Changed" errors.
* **Short Alias:** Standardizes commands under `t` (or the shortcut `td`).

---

## 📂 Installation

### 1. Setup Scripts
Place all script files (`tool_main.sh`, `lib_ssh.sh`, `process_deploy.sh`, `deploy_server.sh`, `deploy_client.sh`, `deploy_database.sh`, `process_dnfupdate.sh`) into `~/scripts/`.

### 2. Fix Line Endings
```bash
cd ~/scripts
sed -i 's/\r$//' *.sh
chmod +x *.sh