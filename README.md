# Custom Automation Tool (`t`)

A modular shell script suite for automating Java WAR deployments, Node.js Client builds, Database migrations, SSH key management, and maintaining a personal command library.

## 🌟 Features at a Glance

* [cite_start]**Context-Aware Deployment:** Detects if you are in a Server, Client, or Database repo and runs the correct build/deploy logic automatically.
* [cite_start]**Self-Healing SSH:** Automatically attempts to fix "Host Identification Changed" errors and installs missing keys.
* [cite_start]**Knowledge Base:** A built-in "Cheat Sheet" engine with fuzzy search (`tf`).
* [cite_start]**Remote Editing:** Edit remote files directly in your local IntelliJ (via SSHFS) or terminal editors.
* [cite_start]**VM Provisioning:** One-command setup (`initvm`) to prepare a fresh VM for development (Root, Postgres, Tomcat).
* [cite_start]**Docker Optimization:** Reclaims root partition space by migrating data to a larger partition[cite: 20].

---

## 🚀 Installation

1.  [cite_start]**File Setup:** Place all scripts in `~/scripts/`.
2.  [cite_start]**Configure Aliases:** Run `source ~/scripts/tool_install.sh` to register `t`, `td`, `tf`, and `te`.

---

## 📖 Command Reference

### ⚡ Core Commands

#### `t deploy <IP>` (Alias: `td`)
* [cite_start]**Function:** Smart Deployment Router.
  | Mode | Directory Name Requirement | File Requirement | Action |
  | :--- | :--- | :--- | :--- |
  | **SERVER** | Folder named **`server`** | Folder **`./dcTrackApp`** | Maven Build -> SCP WAR -> Restart Tomcat |
  | **CLIENT** | Path contains **`client`** | **`./package.json`** | NPM Build -> SCP `dist/` -> Set Perms |
  | **DB** | *No restriction* | **`./.../liquibase/changesets`** | Rsync XMLs -> Remote Migration |

#### `t docker <IP> [subcommand]`
* [cite_start]**Function:** Docker Platform Orchestration[cite: 15, 17].
* [cite_start]**`install`**: Installs Docker and configures the Nexus registry[cite: 15].
* [cite_start]**`env`**: Deploys the environment, syncs `env.dev`, and toggles image/volume modes[cite: 21].
* [cite_start]**`optimize`**: Moves Docker storage to a larger partition via bind mounts[cite: 20].

#### `t edit <IP> [path]` (Alias: `te`)
* [cite_start]**Function:** Remote File Editor[cite: 16].
* **Detail:** Opens remote files. [cite_start]If no path is provided, it shows a **History Menu** of recently edited files[cite: 16].

#### `t viewlog <IP>` (Alias: `t log`)
* [cite_start]**Function:** Interactive Log Viewer.

---

### 🛠️ Admin & Init
#### `t initvm <IP>`
* [cite_start]**Function:** Master provisioning command (Root + Postgres + Tomcat).