fermentrack-tools
============

Various tools to install/configure Fermentrack

**Installation Scripts:**
* **install.sh** - This is a stand-alone bash script that will install Fermentrack onto a Raspbian distro
* **update-tools-repo.sh** - This is a stand-alone bash script that will update fermentrack-tools to the latest version
* **install-legacy-app-support.sh** - This modifies Apache's default virtualhost configuration & ports.conf to run on a different port from Nginx
* **automated_install/auto-install.sh** - This is a bash script that is intended to be called via `curl -L install.fermentrack.com | sudo bash`

**Nginx Config Files:**
* **default-fermentrack** - This is the default nginx configuration file for Fermentrack and runs the app on port 80 from the default installation location (/home/*user*/fermentrack)
* **optional-apache** - This tells nginx to open port 81 for the purpose of serving files that are housed at the default location for Apache (/var/www/html). This allows apps that were previously served by Apache to be easily served by nginx instead.


## Automated Fermentrack Installation Instructions

Want to quickly install Fermentrack onto your Raspberry Pi? Installation can now be completed with one easy command:

1. Log into your Raspberry Pi via SSH (or bring up the terminal)
2. Run `curl -L install.fermentrack.com | sudo bash`
3. Done!

## Manual Fermentrack Installation Instructions

Prefer to install everything manually? No problem. Just run the following and you'll be up and running quickly:

1. Log into your Raspberry Pi via SSH (or bring up the terminal)
2. Run `sudo apt-get update` and 
3. Run `sudo apt-get install -y git-core build-essential python-dev python-virtualenv`
4. Clone the `fermentrack-tools` repo using `git clone`
5. Run `sudo fermentrack-tools/install.sh`
6. Follow the prompts on screen to complete installation
7. Done!


## Note from Thorrak
This script was originally based on the fantastic brewpi-script by Elco/Freeder. Since then, it has been modified to install Fermentrack (instead of brewpi-www and brewpi-script) and utilize scripts in those repos to manage updates.

The automated installer was inspired by the Pi-Hole project. 

**PLEASE NOTE** - Piping anything - especially from a website - to `bash` is dangerous -- and especially so when piping to `sudo bash`. If you feel more comfortable installing things manually, please do so.


## Legacy Apache (Raspberry Pints, brewpi-www, & Others) App Support

Unlike RaspberryPints, brewpi-www, and certain other applications, Fermentrack is designed to run using nginx instead of Apache. To support installing these applications alongside Fermentrack a sample nginx configuration file is included which replicates the environment expected by Apache.

Although this method can be used to run both Fermentrack and legacy BrewPi-www on the same Raspberry Pi, this is not recommended as it can result in unexpected behavior on controllers used by both applications.

To set up support for legacy (apache) applications, use the instructions below:

### Automated Legacy Support Installation

1. Log into your Raspberry Pi via SSH (or bring up the terminal)
2. Run `curl -L install-legacy-support.fermentrack.com | sudo bash`
3. Done!

### Manual Legacy Support Installation
1. Log into your Raspberry Pi via SSH (or bring up the terminal)
2. Clone the `fermentrack-tools` repo using `git clone`
3. Run `sudo fermentrack-tools/install-legacy-support.sh`
4. Follow the prompts on screen to complete installation
5. Done!

