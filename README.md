# Custom Automation Tool (`t`)

A modular shell script suite for automating Java WAR deployments, Node.js Client builds, Database migrations, SSH key management, and maintaining a personal command library.

## 🌟 Features at a Glance

* **Context-Aware Deployment:** Detects if you are in a Server, Client, or Database repo and runs the correct build/deploy logic automatically.
* **Self-Healing SSH:** Automatically attempts to fix "Host Identification Changed" errors and installs missing keys.
* **Knowledge Base:** A built-in "Cheat Sheet" engine with fuzzy search (`tf`).
* **Remote Editing:** Edit remote files directly in your local IntelliJ (via SSHFS) or terminal editors.
* **VM Provisioning:** One-command setup (`initvm`) to prepare a fresh VM for development (Root, Postgres, Tomcat).
* **JProfiler Integration:** Smart profiling setup that adapts to the target's Java version.
* **Docker Optimization:** Reclaims root partition space by migrating data to a larger partition.

---

## 🚀 Installation

1.  **File Setup:** Place all scripts in `~/scripts/`.
2.  **Configure Aliases:** Run `source ~/scripts/tool_install.sh` to register `t`, `td`, `tf`, and `te`.

---

## 📖 Command Reference

### ⚡ Core Commands

#### `t deploy <IP>` (Alias: `td`)
* **Function:** Smart Deployment Router.
  | Mode | Directory Name Requirement | File Requirement | Action |
  | :--- | :--- | :--- | :--- |
  | **SERVER** | Folder named **`server`** | Folder **`./dcTrackApp`** | Maven Build -> SCP WAR -> Restart Tomcat |
  | **CLIENT** | Path contains **`client`** | **`./package.json`** | NPM Build -> SCP `dist/` -> Set Perms |
  | **DB** | *No restriction* | **`./.../liquibase/changesets`** | Rsync XMLs -> Remote Migration |

#### `t docker <IP> [subcommand]`
* **Function:** Docker Platform Orchestration.
* **`install`**: Installs Docker and configures the Nexus registry.
* **`env`**: Deploys the environment, syncs `env.dev`, and toggles image/volume modes.
* **`optimize`**: Moves Docker storage to a larger partition via bind mounts.

#### `t edit <IP> [path]` (Alias: `te`)
* **Function:** Remote File Editor.
* **Detail:** Opens remote files. If no path is provided, it shows a **History Menu** of recently edited files.

#### `t viewlog <IP>` (Alias: `t log`)
* **Function:** Interactive Log Viewer.

---

### 🛠️ Admin & Init

#### `t initvm <IP>`
* **Function:** Master provisioning command (Root + Postgres + Tomcat).

#### `t jprofiler <IP> [off]`
* **Function:** Configure Remote JProfiler (Port 8849).
* **Auto-Detection:**
    * **Modern (JDK 21+):** Updates `setenv.sh` with `-agentpath` and restarts Tomcat.
    * **Legacy (JDK 17-):** Uses `jpenable` to attach to the running process (No restart required).
* **Disable:** Run `t jprofiler <IP> off` to remove the agent configuration and restart the service.