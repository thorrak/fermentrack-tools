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



package_name="Fermentrack"
github_repo="https://github.com/thorrak/fermentrack.git"
github_branch="master"
green=$(tput setaf 76)
red=$(tput setaf 1)
tan=$(tput setaf 3)
reset=$(tput sgr0)
myPath="$( cd "$( dirname "${BASH_SOURCE[0]}")" && pwd )"

############## Command Line Options Parser

INTERACTIVE=0


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
  echo "Welcome to the Fermentrack Python 3 upgrade script. This script will install Python 3 to."
  echo "replace the Python 2 installation that was available previously. You should only need to"
  echo "run this script once - and then only for older Fermentrack installations."
  echo ""
  echo "Please note - Your existing virtualenv at ${installPath}/venv will be deleted."
  echo "If you have any other apps using this virtualenv, you will need to check them to ensure"
  echo "they still work. (That said, this is not common.)"
  echo ""
  echo "For more information about Fermentrack please visit: http://fermentrack.com/"
  echo
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
            exit 1
        fi
    fi
    echo

}


# Check for network connection
verifyInternetConnection() {
  printinfo "Checking for Internet connection: "
  ping -c 3 github.com &>> install.log
  if [ $? -ne 0 ]; then
      echo
      printerror "Could not ping github.com. Are you sure you have a working Internet connection?"
      printerror "Installer will exit, because it needs to fetch packages from the internet"
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
        apt-key update &>> install.log||die
        printinfo "'apt-key update' ran successfully."
        apt-get update &>> install.log||die
        printinfo "'apt-get update' ran successfully."
    fi
    # Installing the nginx stack along with everything we need for circus, etc.
    printinfo "apt is updated - installing python3-venv, python3-dev, and a handful of other packages."
    printinfo "(This may take a few minutes during which everything will be silent) ..."

    # For the curious:
    # git-core enables us to get the code from git (har har)
    # build-essential allows for building certain python (& other) packages
    # avrdude is used to flash Arduino-based devices

    apt-get install -y git-core build-essential redis-server avrdude &>> install.log || die

    # bluez and python-bluez are for bluetooth support (for Tilt)
    # libcap2-bin is additionally for bluetooth support (for Tilt)
    # python-scipy and python-numpy are for Tilt configuration support

    apt-get install -y bluez libcap2-bin &>> install.log || die
    apt-get install -y python3-venv python3-dev python3-zmq python3-scipy python3-numpy

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
    printerror "After rebooting, run this installation again."
    printerror "Insufficient free space, exiting..."
    exit 1
  fi
  echo
}

removeOldPythonVenv() {
  # Set up virtualenv directory
  printinfo "Removing old virtualenv directory..."
  cd "$installPath"
  sudo -u ${fermentrackUser} -H rm -rf ${installPath}/venv/
  echo
}

createPythonVenv() {
  # Set up virtualenv directory
  printinfo "Creating virtualenv directory..."
  cd "$installPath"
  # For specific gravity sensor support, we want --system-site-packages
  # ...but that doesn't work in certain installations of Raspbian. Instead, we'll rig it a bit.
  # sudo -u ${fermentrackUser} -H python3 -m venv ${installPath}/venv --system-site-packages
  sudo -u ${fermentrackUser} -H python3 -m venv ${installPath}/venv
  sudo -u ${fermentrackUser} -H ln -s /usr/lib/python3/dist-packages/numpy* ${installPath}/venv/lib/python*/site-packages
  sudo -u ${fermentrackUser} -H ln -s /usr/lib/python3/dist-packages/scipy* ${installPath}/venv/lib/python*/site-packages
  echo
}

setPythonSetcap() {
  printinfo "Enabling python to query bluetooth without being root"

  PYTHON3_INTERPRETER="$(readlink -e $installPath/venv/bin/python)"
  if [ -a ${PYTHON3_INTERPRETER} ]; then
    sudo setcap cap_net_raw+eip "$PYTHON3_INTERPRETER"
  fi

}



# Clone Fermentrack repositories
updateRepo() {
  printinfo "Downloading most recent Fermentrack codebase..."
  cd "$installPath"
    sudo -u ${fermentrackUser} -H sh -c "cd ~/fermentrack ; git fetch ; git pull"||die
  echo
}



# Run the upgrade script within Fermentrack
runFermentrackUpgrade() {
  printinfo "Running upgrade.sh from the script repo to finalize the install."
  printinfo "This may take up to an hour during which everything will be silent..."
  if [ -a "$installPath"/fermentrack/utils/upgrade3.sh ]; then
    cd "$installPath"/fermentrack/utils/
    sudo -u ${fermentrackUser} -H bash "$installPath"/fermentrack/utils/upgrade3.sh &>> install.log
  else
    printerror "Could not find fermentrack/utils/upgrade3.sh!"
    exit 1
  fi
  echo
}


installationReport() {
#  MYIP=$(/sbin/ifconfig|egrep -A 1 'eth|wlan'|awk -F"[Bcast:]" '/inet addr/ {print $4}')
  MYIP=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')
  echo "Done installing Fermentrack!"
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


fermentrackUser="fermentrack"
installPath="/home/${fermentrackUser}"
scriptversion=$(git log --oneline -n1)
printinfo "Configuring under user ${fermentrackUser}"
printinfo "Configuring in directory $installPath"
echo


verifyInternetConnection
getAptPackages
verifyFreeDiskSpace

removeOldPythonVenv
createPythonVenv
setPythonSetcap
updateRepo

runFermentrackUpgrade

installationReport
sleep 1s
