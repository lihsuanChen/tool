# Custom Automation Tool (`t`)

A modular shell script suite for automating Java WAR deployments, Node.js Client builds, system updates, and SSH key management.

## 🚀 Features

* **Context-Aware Deployment:** Automatically detects if you are in the **Server** or **Client** repository and triggers the correct build/deploy workflow.
* **System Updates:** Transfers and executes maintenance scripts (`dnfupdate.sh`) on remote hosts.
* **Smart SSH:** Auto-detects missing keys, handles `ssh-copy-id`, and auto-fixes "Host Identification Changed" errors.
* **Short Alias:** standardizes commands under the simple `t` alias.

---

## 📂 Installation

### 1. Setup Scripts
Place all script files (`tool_main.sh`, `lib_ssh.sh`, `process_deploy.sh`, `process_dnfupdate.sh`, `setup_alias.sh`) into a directory, e.g., `~/scripts/`.

### 2. Fix Line Endings (Critical)
If you copied these files from Windows, run this command to remove invisible carriage returns:
```bash
cd ~/scripts
sed -i 's/\r$//' *.sh
chmod +x *.sh