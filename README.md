# Custom Automation Tool (`t`)

A modular shell script suite for automating Java WAR deployments, Node.js Client builds, Database migrations, and SSH key management.

## 🚀 Features

* **Context-Aware Deployment:** Automatically detects if you are in the **Server**, **Client**, or **Database** repository and triggers the correct workflow.
* **System Updates:** Transfers and executes maintenance scripts (`dnfupdate.sh`) on remote hosts.
* **Smart SSH:** Auto-detects missing keys, handles `ssh-copy-id`, and auto-fixes "Host Identification Changed" errors.
* **Short Alias:** Standardizes all commands under the simple `t` alias.

---

## 📂 Installation

### 1. Setup Scripts
Place all script files (`tool_main.sh`, `lib_ssh.sh`, `process_deploy.sh`, `process_dnfupdate.sh`, `setup_alias.sh`) into `~/scripts/`.

### 2. Fix Line Endings
If copied from Windows, run:
```bash
cd ~/scripts
sed -i 's/\r$//' *.sh
chmod +x *.sh