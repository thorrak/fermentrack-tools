#!/usr/bin/env bash

# Copyright 2013 BrewPi
# This file was originally part of BrewPi, and is now part of BrewPi/Fermentrack

# BrewPi is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# BrewPi is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with BrewPi.  If not, see <http://www.gnu.org/licenses/>.

# Fermentrack is free software, and is distributed under the terms of the MIT license.
# A copy of the MIT license should be included with Fermentrack. If not, a copy can be
# reviewed at <https://opensource.org/licenses/MIT>

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.


########################
### This script assumes a clean Raspbian install.
### Freeder, v1.0, Aug 2013
### Elco, Oct 2013
### Using a custom 'die' function shamelessly stolen from http://mywiki.wooledge.org/BashFAQ/101
### Using ideas even more shamelessly stolen from Elco and mdma. Thanks guys!
########################


# For fermentrack, the process will work like this:
# 1. Install the system-wide packages (nginx, etc.)
# 2. Confirm the install settings
# 3. Add the users
# 4. Clone the fermentrack repo
# 5. Set up  virtualenv
# 6. Run the fermentrack upgrade script
# 7. Copy the nginx configuration file & restart nginx


package_name="Fermentrack"
github_repo="https://github.com/thorrak/fermentrack.git"
github_branch="master"
green=$(tput setaf 76)
red=$(tput setaf 1)
tan=$(tput setaf 3)
reset=$(tput sgr0)


############## Command Line Options Parser

INTERACTIVE=1

# Help text
function usage() {
    echo "Usage: $0 [-h] [-n] [-r <repo_url>] [-b <branch>]" 1>&2
    echo "Options:"
    echo "  -h               This help"
    echo "  -n               Run non interactive installation"
    echo "  -r <repo_url>    Specify fermentrack repository (only for development)"
    echo "  -b <branch>      Branch used (only for development or testing)"
    exit 1
}

while getopts "nhr:b:" opt; do
  case ${opt} in
    n)
      INTERACTIVE=0  # Silent/Non-interactive Mode
      ;;
    r)
      github_repo=$OPTARG
      ;;
    b)
      github_branch=$OPTARG
      ;;
    h)
      usage
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      usage
      exit 1
      ;;
  esac
done

shift $((OPTIND-1))




printinfo() {
  printf "::: ${green}%s${reset}\n" "$@"
}


printwarn() {
 printf "${tan}*** WARNING: %s${reset}\n" "$@"
}


printerror() {
 printf "${red}*** ERROR: %s${reset}\n" "$@"
}


# Functions
warn() {
  local fmt="$1"
  command shift 2>/dev/null
  echo "${red}*** ----------------------------------${reset}"
  echo "${red}*** ERROR ERROR ERROR ERROR ERROR ***${reset}"
  echo -e "${red}$fmt\n" "${@}${reset}"
  echo "${red}*** ----------------------------------${reset}"
  echo "${red}*** See above lines for error message${reset}"
  echo "${red}*** Setup NOT completed${reset}"
}


die () {
  local st="$?"
  warn "$@"
  exit "$st"
}

welcomeMessage() {
  echo -n "${tan}"
  cat << "EOF"
 _____                              _                  _    
|  ___|__ _ __ _ __ ___   ___ _ __ | |_ _ __ __ _  ___| | __
| |_ / _ \ '__| '_ ` _ \ / _ \ '_ \| __| '__/ _` |/ __| |/ /
|  _|  __/ |  | | | | | |  __/ | | | |_| | | (_| | (__|   < 
|_|  \___|_|  |_| |_| |_|\___|_| |_|\__|_|  \__,_|\___|_|\_\

EOF
  echo -n "${reset}"
  echo "Welcome to the installation of Fermentrack. This script will install fermentrack."
  echo "A new user will be created and Fermentrack will be installed in that users home directory."
  echo "When the installation is done with no errors Fermentrack is started and monitored automatically"
  echo "For more information about Fermentrack please visit: https://github.com/thorrak/fermentrack"
  echo
  if [[ ${INTERACTIVE} -eq 1 ]]; then  # Don't ask this if we're running in noninteractive mode
      read -p "Do you want to continue to install Fermentrack? [y/N] " yn
      case "$yn" in
        y | Y | yes | YES| Yes ) printinfo "Ok, let's go!";;
        * ) exit;;
      esac
  fi
}


verifyRunAsRoot() {
    # verifyRunAsRoot does two things - First, it checks if the script was run by a root user. Assuming it wasn't,
    # then it attempts to relaunch itself as root.
    if [[ ${EUID} -eq 0 ]]; then
        printinfo "This script was launched as root. Continuing installation."
    else
        printinfo "This script was called without root privileges. It installs and updates several packages,"
        printinfo "creates user accounts and updates system settings. To continue this script will now attempt"
        printinfo "to use 'sudo' to relaunch itself as root. Please check the contents of this script for any"
        printinfo "concerns with this requirement. Please be sure to access this script from a trusted source."
        echo

        if command -v sudo &> /dev/null; then
            # TODO - Make this require user confirmation before continuing
            printinfo "This script will now attempt to relaunch using sudo."
            exec sudo bash "$0" "$@"
            exit $?
        else
            printerror "The sudo utility does not appear to be available on this system, and thus installation cannot continue."
            printerror "Please run this script as root and it will be automatically installed."
            printerror "You should be able to do this by running '${install_curl_command}'"
            exit 1
        fi
    fi
    echo

}


# Check for network connection
verifyInternetConnection() {
  printinfo "Checking for Internet connection: "
  ping -c 3 github.com &> /dev/null
  if [ $? -ne 0 ]; then
      echo
      printerror "Could not ping github.com. Are you sure you have a working Internet connection?"
      printerror "Installer will exit, because it needs to fetch code from github.com"
      exit 1
  fi
  printinfo "Internet connection Success!"
  echo
}


# Check if installer is up-to-date
verifyInstallerVersion() {
  printinfo "Checking whether this script is up to date..."
  unset CDPATH
  myPath="$( cd "$( dirname "${BASH_SOURCE[0]}")" && pwd )"
  printinfo ""$myPath"/update-tools-repo.sh start."
  bash "$myPath"/update-tools-repo.sh
  printinfo ""$myPath"/update-tools-repo.sh end."
  if [ $? -ne 0 ]; then
    printerror "The update script was not up-to-date, but it should have been updated. Please re-run install.sh."
    exit 1
  fi
  echo
}


# getAptPackages runs apt-get update, and installs the basic packages we need to continue the Fermentrack install
getAptPackages() {
    printinfo "Installing dependencies using apt-get"
    lastUpdate=$(stat -c %Y /var/lib/apt/lists)
    nowTime=$(date +%s)
    if [ $(($nowTime - $lastUpdate)) -gt 604800 ] ; then
        printinfo "Last 'apt-get update' was awhile back. Updating now. (This may take a minute)"
        sudo apt-key update &> /dev/null||die
        printinfo "'apt-key update' ran successfully."
        sudo apt-get update &> /dev/null||die
        printinfo "'apt-get update' ran successfully."
    fi
    # Installing the nginx stack along with everything we need for circus, etc.
    printinfo "apt is updated - installing git-core, nginx, build-essential, python-dev, and python-virtualenv."
    printinfo "(This may take a few minutes during which everything will be silent) ..."
    sudo apt-get install -y git-core build-essential python-dev python-virtualenv python-pip nginx libzmq-dev libevent-dev rabbitmq-server &> /dev/null || die
    printinfo "All packages installed successfully."
    echo
}


verifyFreeDiskSpace() {
  printinfo "Verifying free disk space..."
  local required_free_kilobytes=512000
  local existing_free_kilobytes=$(df -Pk | grep -m1 '\/$' | awk '{print $4}')

  # - Unknown free disk space , not a integer
  if ! [[ "${existing_free_kilobytes}" =~ ^([0-9])+$ ]]; then
    printerror "Unknown free disk space!"
    printerror "We were unable to determine available free disk space on this system."
    exit 1
  # - Insufficient free disk space
  elif [[ ${existing_free_kilobytes} -lt ${required_free_kilobytes} ]]; then
    printerror "Insufficient Disk Space!"
    printerror "Your system appears to be low on disk space. ${package_name} recommends a minimum of $required_free_kilobytes KB."
    printerror "You only have ${existing_free_kilobytes} KB free."
    printerror "If this is a new install you may need to expand your disk."
    printerror "Try running 'sudo raspi-config', and choose the 'expand file system option'"
    printerror "After rebooting, run this installation again. (${install_curl_command})"
    printerror "Insufficient free space, exiting..."
    exit 1
  fi
  echo
}


verifyInstallPath() {
  if [[ ${INTERACTIVE} -eq 1 ]]; then  # Don't ask if we're in non-interactive mode
      if [ -d "$installPath" ]; then
        if [ "$(ls -A ${installPath})" ]; then
          read -p "Install directory is NOT empty, are you SURE you want to use this path? [y/N] " yn
          case "$yn" in
              y | Y | yes | YES| Yes ) printinfo "Ok, we warned you!";;
              * ) exit;;
          esac
        fi
      fi
      echo
  fi
}


createConfigureUser() {
  ### Create/configure user accounts
  printinfo "Creating and configuring user accounts."

  if id -u $fermentrackUser >/dev/null 2>&1; then
    printinfo "User '$fermentrackUser' already exists, skipping..."
  else
    useradd -m -G dialout $fermentrackUser -s /bin/bash||die
    # Disable direct login for this user to prevent hijacking if password isn't changed
    passwd -d $fermentrackUser||die
  fi
  # add pi user to fermentrack and www-data group
  if id -u pi >/dev/null 2>&1; then
    usermod -a -G www-data $fermentrackUser||die
  fi
  echo
}


backupOldInstallation() {
  printinfo "Checking install directories"
  dirName=$(date +%F-%k:%M:%S)
  if [ "$(ls -A ${installPath})" ]; then
    printinfo "Script install directory is NOT empty, backing up to this users home dir and then deleting contents..."
      if [ ! -d ~/fermentrack-backup ]; then
        mkdir -p ~/fermentrack-backup
      fi
      mkdir -p ~/fermentrack-backup/"$dirName"
      cp -R "$installPath" ~/fermentrack-backup/"$dirName"/||die
      rm -rf "$installPath"/*||die
      find "$installPath"/ -name '.*' | xargs rm -rf||die
  fi
  echo
}


fixPermissions() {
  printinfo "Making sure everything is owned by $fermentrackUser"
  chown -R $fermentrackUser:$fermentrackUser "$installPath"||die
  # Set sticky bit! nom nom nom
  find "$installPath" -type d -exec chmod g+rwxs {} \;||die
  echo
}


# Clone Fermentrack repositories
cloneRepository() {
  printinfo "Downloading most recent $package_name codebase..."
  cd "$installPath"
  if [ "$github_repo" != "master" ]; then
    sudo -u $fermentrackUser git clone -b ${github_branch} ${github_repo} "$installPath/fermentrack"||die
  else
    sudo -u $fermentrackUser git clone ${github_repo} "$installPath/fermentrack"||die
  fi
  echo
}


createPythonVenv() {
  # Set up virtualenv directory
  printinfo "Creating virtualenv directory..."
  cd "$installPath"
  # Supposedly, --no-site-packages is now default behavior - including it nonetheless just in case
  sudo -u $fermentrackUser virtualenv --no-site-packages "venv"
  echo
}


# Create secretsettings.py file
makeSecretSettings() {
  printinfo "Running make_secretsettings.sh from the script repo"
  if [ -a "$installPath"/fermentrack/utils/make_secretsettings.sh ]; then
    cd "$installPath"/fermentrack/utils/
    sudo -u $fermentrackUser bash "$installPath"/fermentrack/utils/make_secretsettings.sh
  else
    printerror "Could not find fermentrack/utils/make_secretsettings.sh!"
    # TODO: decide if this is a fatal error or not
    exit 1
  fi
  echo
}


# Run the upgrade script within Fermentrack
runFermentrackUpgrade() {
  printinfo "Running upgrade.sh from the script repo to finalize the install."
  if [ -a "$installPath"/fermentrack/utils/upgrade.sh ]; then
    cd "$installPath"/fermentrack/utils/
    sudo -u $fermentrackUser bash "$installPath"/fermentrack/utils/upgrade.sh
  else
    printerror "Could not find fermentrack/utils/upgrade.sh!"
    exit 1
  fi
  echo
}


# Check for insecure SSH key
# TODO: Check if this is still needed, newer versions of rasbian don't have this problem.
fixInsecureSSH() {
  defaultKey="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDLNC9E7YjW0Q9btd9aUoAg++/wa06LtBMc1eGPTdu29t89+4onZk1gPGzDYMagHnuBjgBFr4BsZHtng6uCRw8fIftgWrwXxB6ozhD9TM515U9piGsA6H2zlYTlNW99UXLZVUlQzw+OzALOyqeVxhi/FAJzAI9jPLGLpLITeMv8V580g1oPZskuMbnE+oIogdY2TO9e55BWYvaXcfUFQAjF+C02Oo0BFrnkmaNU8v3qBsfQmldsI60+ZaOSnZ0Hkla3b6AnclTYeSQHx5YqiLIFp0e8A1ACfy9vH0qtqq+MchCwDckWrNxzLApOrfwdF4CSMix5RKt9AF+6HOpuI8ZX root@raspberrypi"

  if grep -q "$defaultKey" /etc/ssh/ssh_host_rsa_key.pub; then
    printinfo "Replacing default SSH keys. You will need to remove the previous key from known hosts on any clients that have previously connected to this rpi."
    if rm -f /etc/ssh/ssh_host_* && dpkg-reconfigure openssh-server; then
      printinfo "Default SSH keys replaced."
      echo
    else
      printwarn "Unable to replace SSH key. You probably want to take the time to do this on your own."
    fi
  fi
}


# Set up nginx
setupNginx() {
  printinfo "Copying nginx configuration to /etc/nginx and activating."
  rm -f /etc/nginx/sites-available/default-fermentrack &> /dev/null
  # Replace all instances of 'brewpiuser' with the fermentrackUser we set and save as the nginx configuration
  sed "s/brewpiuser/${fermentrackUser}/" "$myPath"/nginx-configs/default-fermentrack > /etc/nginx/sites-available/default-fermentrack
  rm -f /etc/nginx/sites-enabled/default &> /dev/null
  ln -s /etc/nginx/sites-available/default-fermentrack /etc/nginx/sites-enabled/default-fermentrack
  service nginx restart
}


setupCronCircus() {
  # Install CRON job to launch Circus
  printinfo "Running updateCronCircus.sh from the script repo"
  if [ -f "$installPath"/fermentrack/brewpi-script/utils/updateCronCircus.sh ]; then
    sudo -u $fermentrackUser bash "$installPath"/fermentrack/brewpi-script/utils/updateCronCircus.sh add2cron
    printinfo "Starting circus process monitor."
    sudo -u $fermentrackUser bash "$installPath"/fermentrack/brewpi-script/utils/updateCronCircus.sh start
  else
    # whops, something is wrong.. 
    printerror "Could not find updateCronCircus.sh!"
    exit 1
  fi
  echo
}


installationReport() {
  MYIP=$(/sbin/ifconfig|egrep -A 1 'eth|wlan'|awk -F"[Bcast:]" '/inet addr/ {print $4}')
  echo "Done installing Fermentrack!"
  echo
  echo "====================================================================================================="
  echo "Review the log above for any errors, otherwise, your initial environment install is complete!"
  echo
  echo "The fermentrack user has been set up with no password. Use 'sudo -u ${fermentrackUser} -i'"
  echo "from this user to access the fermentrack user"
  echo "To view Fermentrack, enter http://${MYIP} into your web browser"
  echo
  echo " - Fermentrack frontend    : http://${MYIP}"
  echo " - Fermentrack user        : ${fermentrackUser}"
  echo " - Installation path       : ${installPath}/fermentrack"
  echo " - Fermentrack Version     : $(git -C ${installPath}/fermentrack log --oneline -n1)"
  echo " - Install Script Version  : ${scriptversion}"
  echo ""
  echo "Happy Brewing!"
  echo ""
}


## ------------------- Script "main" starts here -----------------------
# Create install log file
verifyRunAsRoot
welcomeMessage

exec > >(tee -i install.log)
exec 2>&1

if [[ ${INTERACTIVE} -eq 1 ]]; then  # Don't ask questions if we're running in noninteractive mode
    printinfo "To accept the default answer, just press Enter."
    printinfo "The default is capitalized in a Yes/No question: [Y/n]"
    printinfo "or shown between brackets for other questions: [default]"
    echo

    date=$(date)
    read -p "The time is currently set to $date. Is this correct? [Y/n]" choice
    case "$choice" in
      n | N | no | NO | No )
        dpkg-reconfigure tzdata;;
      * )
    esac

    printinfo "All scripts associated with BrewPi & Fermentrack are now installed to a user's home directory"
    printinfo "Hitting 'enter' will accept the default option in [brackets] (recommended)."
    printwarn "Any data in the user's home directory may be ERASED during install!"
    echo
    read -p "What user would you like to install BrewPi under? [fermentrack]: " fermentrackUser
    if [ -z "$fermentrackUser" ]; then
      fermentrackUser="fermentrack"
    else
      case "$fermentrackUser" in
        y | Y | yes | YES| Yes )
            fermentrackUser="fermentrack";; # accept default when y/yes is answered
        * )
            ;;
      esac
    fi
else  # If we're in non-interactive mode, default the user
    fermentrackUser="fermentrack"
fi

installPath="/home/$fermentrackUser"
scriptversion=$(git log --oneline -n1)
printinfo "Configuring under user $fermentrackUser"
printinfo "Configuring in directory $installPath"
echo


verifyInternetConnection
verifyInstallerVersion
getAptPackages
verifyFreeDiskSpace
verifyInstallPath
createConfigureUser
backupOldInstallation
fixPermissions
cloneRepository
createPythonVenv
makeSecretSettings
runFermentrackUpgrade
fixInsecureSSH
setupNginx
setupCronCircus
installationReport

