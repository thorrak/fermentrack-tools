fermentrack-tools
============

Various tools to install/configure Fermentrack

**Installation Scripts:**
* **install-docker.sh** - This script installs both Docker and Fermentrack, along with the other applications Fermentrack requires
* **docker-update.sh** - This script updates the Fermentrack docker stack to the latest version
* **docker-create-superuser.sh** - This script creates a new Fermentrack superuser (in case you forget your password)
* **automated_install/auto-docker-install.sh** - This is a bash script that is intended to be called via `curl -L install.fermentrack.com | bash`


## Automated Fermentrack Installation Instructions

Want to quickly install Fermentrack onto your Raspberry Pi? Installation can now be completed with one easy command:

1. Log into your Raspberry Pi via SSH (or bring up the terminal)
2. Run `curl -L install.fermentrack.com | bash`
3. Done!

## Manual Fermentrack Installation Instructions

Prefer to install everything without piping a website to bash? No problem. Just run the following and you'll be up and running quickly:

1. Log into your Raspberry Pi via SSH (or bring up the terminal)
2. Run `sudo apt-get update` and `sudo apt-get upgrade`
3. Run `sudo apt-get install -y git build-essential`
4. Clone the `fermentrack-tools` repo using `git clone`
5. Run `fermentrack-tools/install-docker.sh`
6. Follow the prompts on screen to complete installation
7. Done!

