# Custom Automation Tool (`t`)

A modular shell script suite for automating Java WAR deployments, Node.js Client builds, Database migrations, SSH key management, and maintaining a personal command library.

## 🚀 Features at a Glance

* **Context-Aware Deployment:** Detects if you are in a Server, Client, or Database repo and runs the correct build/deploy logic automatically.
* **Self-Healing SSH:** Automatically attempts to fix "Host Identification Changed" errors and installs missing keys.
* **Knowledge Base:** A built-in "Cheat Sheet" engine with fuzzy search (`tf`).
* **VM Provisioning:** One-command setup (`initvm`) to prepare a fresh VM for development (Root, Postgres, Tomcat).

---

## 📂 Installation

1.  **File Setup:** Place all scripts in `~/scripts/`:
    * `tool_main.sh`, `tool_help.sh`, `tool_install.sh`
    * `m1_lib_ssh.sh`, `m2_process_dnfupdate.sh`, `m3_tool_cheatsheet.sh`
    * `m4_tool_init_vm.sh`, `m4_tool_postgres.sh`, `m4_tool_tomcat.sh`
    * `m5_process_deploy.sh`, `m5_deploy_server.sh`, `m5_deploy_client.sh`, `m5_deploy_database.sh`
    * `tool_readme.sh`, `tool_viewlog.sh`

2.  **Configure Aliases:**
    Run the installer to register `t`, `td`, and `tf` in your `.bashrc`:
    ```bash
    source ~/scripts/tool_install.sh
    ```

---

## 📖 Command Reference

### 🟢 Core Commands

#### `t deploy <IP>` (Alias: `td`)
* **Function:** Smart Deployment Router.
* **Context Detection Logic:**
  The tool identifies the project type by checking specific "Fingerprints" in your current directory:

| Mode | Directory Name Requirement | File Requirement | Action |
| :--- | :--- | :--- | :--- |
| **SERVER** | Current folder must be named **`server`** | Must contain folder **`./dcTrackApp`** | Maven Build -> SCP WAR -> Restart Tomcat |
| **CLIENT** | Full path must contain string **`client`** | Must contain **`./package.json`** | NPM Build -> SCP `dist/` -> Set Perms |
| **DB** | *No name restriction* | Must contain **`./src/files/opt/raritan/liquibase/changesets`** | Rsync XMLs -> Run Remote Migration |

* **Flags:**
    * `-v <version>`: Force a specific version number (e.g., `td 116 -v 9.3.5`). This is useful if your folder structure implies one version but you want to tag the build differently.

#### `t ssh <IP>`
* **Function:** Connects to the target IP as `root`.
* **Detail:** Auto-installs SSH keys if missing and fixes known_hosts errors automatically.

#### `t find <query>` (Alias: `tf`)
* **Function:** Fuzzy Search Command Library.
* **Detail:** Searches `~/scripts/m3_my_commands.txt` for commands using keywords or synonyms.

#### `t viewlog <IP>` (Alias: `log`)
* **Function:** Interactive Log Viewer.
* **Detail:** Fetches a dynamic list of remote PostgreSQL logs and offers a menu to open them in `lnav` or `glogg`.

---

### 🟠 Admin & Init

#### `t initvm <IP>`
* **Function:** Master provisioning command.
* **Detail:** Runs `rootsetup` + `pgtrust` + `tomcatsetup` in sequence.

#### `t rootsetup <IP>`
* **Function:** Configures Root SSH access.
* **Detail:** Prompts to sync the remote root password with your local bridge password, then enables Root Login in `sshd_config`.

#### `t pgtrust <IP>`
* **Function:** Grants database access.
* **Detail:** Whitelists your specific IP (`/32`) in the remote `pg_hba.conf`.

#### `t tomcatsetup <IP>`
* **Function:** Enables Remote Debugging.
* **Detail:** Configures Tomcat to listen on Port 8000 for JPDA connections.

#### `t dnfupdate <IP>`
* **Function:** System Update.
* **Detail:** Runs the standard DNF update script on the remote host.

---

### 🔵 Configuration

#### `t setpass [IP]`
* **Function:** Updates Bridge Password.
* **Detail:** Securely stores the password for the bridge user (`sunbird`) in `~/.sunbird_auth` so you don't have to type it repeatedly.

#### `t setlogviewer`
* **Function:** Preference Toggles.
* **Detail:** Switches the default log viewer between CLI-based `lnav` and GUI-based `glogg`.