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
PORT="80"
github_repo="https://github.com/thorrak/fermentrack.git"
github_branch="master"
green=$(tput setaf 76)
red=$(tput setaf 1)
tan=$(tput setaf 3)
reset=$(tput sgr0)
myPath="$( cd "$( dirname "${BASH_SOURCE[0]}")" && pwd )"

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
  echo "${red}*** More information in the \"install.log\" file${reset}"
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
  echo "When the installation is done with no errors Fermentrack is started and monitored automatically."
  echo ""
  echo "Please note - Any existing apps that require Apache (including RaspberryPints and BrewPi-www)"
  echo "will be deactivated. If you want support for these apps it can be optionally installed later."
  echo "Please read http://apache.fermentrack.com/ for more information."
  echo ""
  echo "For more information about Fermentrack please visit: http://fermentrack.com/"
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
        printinfo "creates user accounts, and updates system settings. To continue this script will exit now"
        printinfo "and must be relaunched by you using sudo. Please check the contents of this script for any"
        printinfo "concerns with this requirement. Please be sure to access this script from a trusted source."
        echo
        die "Script must be relaunched using sudo "
    fi

}


# Check for network connection
verifyInternetConnection() {
  printinfo "Checking for Internet connection: "
  wget -q --spider --no-check-certificate github.com &>> install.log
  if [ $? -ne 0 ]; then
      echo
      printerror "Could not connect to GitHub. Are you sure you have a working Internet"
      printerror "connection? Installer will exit; it needs to fetch code from GitHub."
      exit 1
  fi
  printinfo "Internet connection Success!"
  echo
}




# getAptPackages runs apt-get update, and installs the basic packages we need to continue the Fermentrack install
getAptPackages() {
    printinfo "Installing dependencies using apt-get"
    lastUpdate=$(stat -c %Y /var/lib/apt/lists)
    nowTime=$(date +%s)
    if [ $(($nowTime - $lastUpdate)) -gt 604800 ] ; then
        printinfo "Last 'apt-get update' was awhile back. Updating now. (This may take a minute)"
        sudo apt-get update &>> install.log||die
        printinfo "'apt-get update' ran successfully."
    fi
    # Installing the nginx stack along with everything we need for circus, etc.
    printinfo "apt is updated - installing git-core, nginx, python-dev, and a handful of other packages."
    printinfo "(This may take a few minutes during which everything will be silent) ..."

    # For the curious:
    # git-core enables us to get the code from git (har har)
    # build-essential allows for building certain python (& other) packages
    # python-dev, python-pip, and python-virtualenv all enable us to run Python scripts
    # python-zmq is used in part by Circus
    # nginx is a webserver
    # redis-server is a key/value store used for gravity sensor & task queue support
    # avrdude is used to flash Arduino-based devices

    sudo apt-get install -y git-core build-essential nginx redis-server avrdude &>> install.log || die

    # bluez and python-bluez are for bluetooth support (for Tilt)
    # libcap2-bin is additionally for bluetooth support (for Tilt)
    # python-scipy and python-numpy are for Tilt configuration support

    sudo apt-get install -y bluez libcap2-bin libbluetooth3 libbluetooth-dev &>> install.log || die
    # apt-get install -y python-bluez python-scipy python-numpy &>> install.log || die

    sudo apt-get install -y python3-venv python3-dev python3-zmq python3-pip &>> install.log || die
    # numpy is now installed from source directly into the venv, but I'd like to switch back to using the packages when
    # possible. We should only -have- to install from source when this (call to apt) doesn't work.
    sudo apt-get install -y python3-scipy python3-numpy &>> install.log || die

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

  if id -u ${fermentrackUser} >/dev/null 2>&1; then
    printinfo "User '${fermentrackUser}' already exists, skipping..."
  else
    sudo useradd -m -G dialout ${fermentrackUser} -s /bin/bash &>> install.log ||die
    # Disable direct login for this user to prevent hijacking if password isn't changed
    sudo passwd -d ${fermentrackUser}||die
  fi
  # add pi user to fermentrack and www-data group
  if id -u pi >/dev/null 2>&1; then
    sudo usermod -a -G www-data ${fermentrackUser}||die
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
  printinfo "Making sure everything is owned by ${fermentrackUser}"
  chown -R ${fermentrackUser}:${fermentrackUser} "$installPath"||die
  # Set sticky bit! nom nom nom
  find "$installPath" -type d -exec chmod g+rwxs {} \;||die
  echo
}


# Clone Fermentrack repositories
cloneRepository() {
  printinfo "Downloading most recent $package_name codebase..."
  cd "$installPath" || exit
  if [ "$github_repo" != "master" ]; then
    sudo -u ${fermentrackUser} -H git clone -b "${github_branch}" ${github_repo} "$installPath/fermentrack"||die
  else
    sudo -u ${fermentrackUser} -H git clone ${github_repo} "$installPath/fermentrack"||die
  fi
  echo
}

forcePipReinstallation() {
  # This forces reinstallation of pip within the virtualenv in case the environment has a "helpful" custom version
  # (I'm looking at you, ubuntu/raspbian...)
  printinfo "Forcing reinstallation of pip within the virtualenv"
  sudo -u ${fermentrackUser} -H ${installPath}/venv/bin/pip install -U --force-reinstall pip
  sudo -u ${fermentrackUser} -H ${installPath}/venv/bin/pip install -U pip
}

createPythonVenv() {
  # Set up virtualenv directory
  printinfo "Creating virtualenv directory..."
  cd "$installPath" || exit

  # Our default PYTHON3_INTERPRETER is 'python3'
  PYTHON3_INTERPRETER="python3"

  # For specific gravity sensor support, we want --system-site-packages
  # ...but that doesn't work in certain installations of Raspbian. Instead, we'll rig it a bit.
  # sudo -u ${fermentrackUser} -H python3 -m venv ${installPath}/venv --system-site-packages
  if command -v python3.7 &> /dev/null; then
    printinfo "Python 3.7 is installed. Using Python 3.7 to create the venv."
    # Note for the future - This check is imperfect at best. We're attempting to preserve Stretch support by explicitly
    # calling for Python 3.7, even though later versions of Raspbian may have later versions of Python. This check will
    # explicitly force the use/linkage of Python 3.7 binaries when available but *shouldn't* fail with higher versions.
    sudo -u ${fermentrackUser} -H python3.7 -m venv ${installPath}/venv

    # Fix the symlinks to only point to Python 3.7
    sudo -u ${fermentrackUser} -H rm ${installPath}/venv/bin/python3
    sudo -u ${fermentrackUser} -H rm ${installPath}/venv/bin/python
    sudo -u ${fermentrackUser} -H ln -s ${installPath}/venv/bin/python3.7 ${installPath}/venv/bin/python
    sudo -u ${fermentrackUser} -H ln -s ${installPath}/venv/bin/python3.7 ${installPath}/venv/bin/python3

    # Setting PYTHON3_INTERPRETER here allows us to explicitly test if numpy is available in python 3.7
    PYTHON3_INTERPRETER="python3.7"
  else
    # We presumably either have a user that skipped all the warnings on Stretch, or have later versions of Python
    # available. Let's just proceed for now. Eventually this check should get rewritten.
    printinfo "Python 3.7 is NOT installed. Using the generic 'Python 3' to create the venv."
    sudo -u ${fermentrackUser} -H python3 -m venv ${installPath}/venv
  fi


  # Before we do anything else - update pip
  forcePipReinstallation

  # I want to specifically install things in this order to the venv
  printinfo "Manually installing PyZMQ and Circus - This could take ~10-15 mins."

  sudo -u ${fermentrackUser} -H  $installPath/venv/bin/python3 -m pip install --no-binary pyzmq pyzmq==19.0.1
  # TODO - version lock the below to match requirements.txt - circus>=0.16.0,<0.17.0
  sudo -u ${fermentrackUser} -H  $installPath/venv/bin/python3 -m pip install circus

  if $PYTHON3_INTERPRETER -c "import numpy" &> /dev/null; then
    # Numpy is available from system packages. Link to the venv
    printinfo "Numpy and Scipy are available through system packages. Linking to those."
    sudo -u ${fermentrackUser} -H ln -s /usr/lib/python3/dist-packages/numpy* ${installPath}/venv/lib/python*/site-packages
    sudo -u ${fermentrackUser} -H ln -s /usr/lib/python3/dist-packages/scipy* ${installPath}/venv/lib/python*/site-packages
  else
    # Numpy is NOT available from system packages. Let's attempt to install manually.
    printinfo "Numpy and Scipy are not available through system packages. Installing manually."
    printinfo "NOTE - This could take 4+ hours. This could have been skipped if you installed"
    printinfo "on a recent version of Raspbian."

    # For manual installs of numpy, we need to have libatlas-base-dev installed
    sudo apt-get install -y libatlas-base-dev &>> install.log || die

    sudo -u ${fermentrackUser} -H $installPath/venv/bin/python3 -m pip install --no-binary numpy numpy==1.18.4
    #sudo -u ${fermentrackUser} -H $installPath/venv/bin/python3 -m pip install --no-binary scipy scipy==1.4.1
  fi
  printinfo "Venv has been created!"

  echo
}

setPythonSetcap() {
  printinfo "Enabling python to query bluetooth without being root"

  PYTHON3_INTERPRETER="$(readlink -e $installPath/venv/bin/python)"
  if [ -a ${PYTHON3_INTERPRETER} ]; then
    sudo setcap cap_net_raw,cap_net_admin+eip "$PYTHON3_INTERPRETER"
  fi

}


# Create secretsettings.py file
makeSecretSettings() {
  printinfo "Running make_secretsettings.sh from the script repo"
  if [ -a "$installPath"/fermentrack/utils/make_secretsettings.sh ]; then
    cd "$installPath"/fermentrack/utils/ || exit
    sudo -u ${fermentrackUser} -H bash "$installPath"/fermentrack/utils/make_secretsettings.sh
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
  printinfo "This may take up to an hour during which everything will be silent..."
  if [ -a "$installPath"/fermentrack/utils/upgrade3.sh ]; then
    cd "$installPath"/fermentrack/utils/ || exit
    sudo -u ${fermentrackUser} -H bash "$installPath"/fermentrack/utils/upgrade3.sh &>> install.log
  else
    printerror "Could not find ~/fermentrack/utils/upgrade3.sh!"
    exit 1
  fi
  echo
}


# Set up nginx
setupNginx() {
  printinfo "Copying nginx configuration to /etc/nginx and activating."
  rm -f /etc/nginx/sites-available/default-fermentrack &> /dev/null
  # Replace all instances of 'brewpiuser' with the fermentrackUser we set and save as the nginx configuration
  sed "s/brewpiuser/${fermentrackUser}/" "$myPath"/nginx-configs/default-fermentrack > /etc/nginx/sites-available/default-fermentrack
  rm -f /etc/nginx/sites-enabled/default &> /dev/null
  ln -sf /etc/nginx/sites-available/default-fermentrack /etc/nginx/sites-enabled/default-fermentrack
  service nginx restart
}


setupCronCircus() {
  # Install CRON job to launch Circus
  printinfo "Running updateCronCircus.sh from the script repo"
  if [ -f "$installPath"/fermentrack/utils/updateCronCircus.sh ]; then
    sudo -u ${fermentrackUser} -H bash "$installPath"/fermentrack/utils/updateCronCircus.sh add2cron
    printinfo "Starting circus process monitor."
    sudo -u ${fermentrackUser} -H bash "$installPath"/fermentrack/utils/updateCronCircus.sh start
  else
    # whoops, something is wrong...
    printerror "Could not find updateCronCircus.sh!"
    exit 1
  fi
  echo
}


find_ip_address() {
  IP_ADDRESSES=($(hostname -I 2>/dev/null))
  echo "Waiting for Fermentrack install to initialize and become responsive."
  echo "Fermentrack may take up to 5 minutes to first boot as the database is being initialized."

  for i in {1..180}; do
    for IP_ADDRESS in "${IP_ADDRESSES[@]}"
    do
      if [[ $IP_ADDRESS != "172."* ]]; then
        FT_COUNT=$(curl -L "http://${IP_ADDRESS}:${PORT}" 2>/dev/null | grep -m 1 -c Fermentrack)
        if [ $FT_COUNT == "1" ] ; then
          echo "found!"
          return
        fi
      fi
    done
    echo -n "."
    sleep 2
  done

  # If we hit this, we didn't find a valid IP address that responded with "Fermentrack" when accessed.
  echo "missing."
  die "Unable to find an initialized, responsive instance of Fermentrack"
}


installationReport() {
  find_ip_address

  if [[ $PORT != "80" ]]; then
    URL="http://${IP_ADDRESS}:${PORT}"
  else
    URL="http://${IP_ADDRESS}"
  fi


  echo "Done installing Fermentrack!"
  echo "====================================================================================================="
  echo "Review the log above for any errors, otherwise, your initial environment install is complete!"
  echo
  echo "The fermentrack user has been set up with no password. Use 'sudo -u ${fermentrackUser} -i'"
  echo "from this user to access the fermentrack user"
  echo "To view Fermentrack, enter ${URL} into your web browser"
  echo
  echo " - Fermentrack frontend    : ${URL}"
  echo " - Fermentrack user        : ${fermentrackUser}"
  echo " - Installation path       : ${installPath}/fermentrack"
  echo " - Fermentrack version     : $(git -C ${installPath}/fermentrack log --oneline -n1)"
  echo " - Install script version  : ${scriptversion}"
  echo " - Install tools path      : ${myPath}"
  echo ""
  echo "Happy Brewing!"
  echo ""
}


## ------------------- Script "main" starts here -----------------------
# Create install log file
verifyRunAsRoot
welcomeMessage

# This one should remove color escape codes from log, but it needs some more
# work so the EOL esc codes also get stripped.
# exec > >( tee >( sed 's/\x1B\[[0-9;]*[JKmsu]//g' >> install.log ) )
exec > >(tee -ai install.log)
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

    printinfo "All scripts associated with Fermentrack are now installed to a user's home directory"
    printinfo "Hitting 'enter' will accept the default option in [brackets] (recommended)."
    printwarn "Any data in the user's home directory may be ERASED during install!"
    echo
    read -p "What user would you like to install Fermentrack under? [fermentrack]: " fermentrackUser
    if [ -z "${fermentrackUser}" ]; then
      fermentrackUser="fermentrack"
    else
      case "${fermentrackUser}" in
        y | Y | yes | YES| Yes )
            fermentrackUser="fermentrack";; # accept default when y/yes is answered
        * )
            ;;
      esac
    fi
else  # If we're in non-interactive mode, default the user
    fermentrackUser="fermentrack"
fi

installPath="/home/${fermentrackUser}"
scriptversion=$(git log --oneline -n1)
printinfo "Configuring under user ${fermentrackUser}"
printinfo "Configuring in directory $installPath"
echo


verifyInternetConnection
getAptPackages
verifyFreeDiskSpace
verifyInstallPath
createConfigureUser
backupOldInstallation
fixPermissions
cloneRepository
fixPermissions
createPythonVenv
setPythonSetcap
makeSecretSettings
runFermentrackUpgrade
setupNginx
fixPermissions
setupCronCircus
installationReport
sleep 1s
