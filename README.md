# Custom Automation Tool (`t`)

A modular shell script suite for automating Java WAR deployments, Node.js Client builds, Database migrations, SSH key management, and maintaining a personal command library.

## 🚀 Features

* **Context-Aware Deployment (`td`):** Automatically detects if you are in a **Server**, **Client**, or **Database** repository and triggers the correct build/deploy workflow.
* **Command Cheatsheet (`tf`):** A built-in knowledge base. Record complex one-liners once, and fuzzy-search them later.
* **Smart SSH:** Auto-detects missing keys, handles `ssh-copy-id`, and auto-fixes "Host Identification Changed" errors.
* **Bridge Security:** Manages the password for the bridge/gateway user (`sunbird`) locally, so you don't have to type it every time.

---

## 📂 Installation

### 1. Setup Scripts
Place all script files into `~/scripts/`:
* `tool_main.sh`, `tool_help.sh`, `tool_cheatsheet.sh`, `lib_ssh.sh`
* `process_deploy.sh`, `deploy_server.sh`, `deploy_client.sh`, `deploy_database.sh`
* `process_dnfupdate.sh`

### 2. Configure Aliases
1.  Make scripts executable:
    ```bash
    cd ~/scripts
    chmod +x *.sh
    sed -i 's/\r$//' *.sh
    ```
2.  Run the setup script to add aliases (`t`, `td`, `tf`) to your `.bashrc`:
    ```bash
    bash ~/scripts/setup_alias.sh
    source ~/.bashrc
    ```

### 3. Create Command Library
Create your personal cheatsheet file:
```bash
touch ~/scripts/my_commands.txt