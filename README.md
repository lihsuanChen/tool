\# Custom Automation Tool (`tool`)



A modular shell script suite for automating Java WAR deployments, system updates, and SSH key management on remote Linux servers.



\## 🚀 Features



\* \*\*Smart Deployment:\*\* Builds Maven projects and automatically deploys the WAR file to a remote Tomcat server.

\* \*\*System Updates:\*\* Transfers and executes maintenance scripts (e.g., `dnfupdate.sh`) on remote hosts.

\* \*\*SSH Management:\*\* Auto-detects missing keys, handles `ssh-copy-id`, and auto-fixes "Host Identification Changed" errors.

\* \*\*Context Aware:\*\* Prevents deployment errors by verifying your current working directory.



---



\## 📂 Installation



\### 1. Setup Scripts

Place all script files (`tool\_main.sh`, `lib\_ssh.sh`, `process\_deploy.sh`, `process\_dnfupdate.sh`, `setup\_alias.sh`) into a single directory, for example: `~/scripts/`.



\### 2. Fix Line Endings (Critical)

If you copied these files from Windows, run this command to remove invisible carriage returns:

```bash

cd ~/scripts

sed -i 's/\\r$//' \*.sh

chmod +x \*.sh

