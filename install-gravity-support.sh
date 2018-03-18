#!/usr/bin/env bash

# TODO - Delete this script as it is no longer necessary

# install-gravity-support.sh
#
# This script attempts to update the Fermentrack environment to incorporate the changes required to support specific
# gravity sensor support (including support for Tilt hydrometers which require specific permissions).

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

# These are currently unused (hence the exclusion from the help text). Eventually, I may use them to make the ports
# configurable.
fermentrack_port=80
legacy_port=81


############## Command Line Options Parser

INTERACTIVE=1

# Help text
function usage() {
    echo "Usage: $0 [-h] [-n]" 1>&2
    echo "Options:"
    echo "  -h               This help"
    echo "  -n               Run non interactive installation"
    exit 1
}

while getopts "nhp:l:" opt; do
  case ${opt} in
    n)
      INTERACTIVE=0  # Silent/Non-interactive Mode
      ;;
    p)
      fermentrack_port=$OPTARG
      ;;
    l)
      legacy_port=$OPTARG
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
  echo "This script installs support for specific gravity sensors within Fermentrack."
  echo "It is only necessary if you installed using an old version of the install script. Once"
  echo "installation completes, you will need to enable specific gravity sensor support from"
  echo "the Fermentrack settings page (the gear icon in the upper right)."
  echo
  if [[ ${INTERACTIVE} -eq 1 ]]; then  # Don't ask this if we're running in noninteractive mode
      read -p "Do you want to continue to install specific gravity sensor support? [y/N] " yn
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
  bash "$myPath"/update-tools-repo.sh &>> install.log
  printinfo ""$myPath"/update-tools-repo.sh end."
  if [ $? -ne 0 ]; then
    printerror "The update script was not up-to-date, but it should have been updated. Please re-run install.sh."
    exit 1
  fi
  echo
}


# Run the upgrade script within Fermentrack
verifyInstallLocation() {
  printinfo "This script requires an installation of Fermentrack to the default directory to complete."
  if [ -a /home/fermentrack/fermentrack/utils/upgrade.sh ]; then
    printinfo "::: Default install location found!"
  else
    printerror "Could not find /home/fermentrack/fermentrack/utils/upgrade.sh!"
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
        apt-key update &>> install.log||die
        printinfo "'apt-key update' ran successfully."
        apt-get update &>> install.log||die
        printinfo "'apt-get update' ran successfully."
    fi
    # Installing the nginx stack along with everything we need for circus, etc.
    printinfo "apt is updated - checking that the packages required for Fermentrack are already installed."
    printinfo "(This may take a few minutes during which everything will be silent) ..."

    # All of the below should already be installed as part of the default Fermentrack install
    # For the curious:
    # git-core enables us to get the code from git (har har)
    # build-essential allows for building certain python (& other) packages
    # python-dev, python-pip, and python-virtualenv all enable us to run Python scripts
    # nginx is a webserver
    # redis-server is a key/value store used for gravity sensor & task queue support
    # avrdude is used to flash Arduino-based devices

    # Technically, this is the first time most users of this script will see redis-server. It's included here for Huey.
    apt-get install -y git-core build-essential python-dev python-virtualenv python-pip nginx redis-server avrdude &>> install.log || die

    # This removes the packages previously used by celery
    printinfo "Removing packages no longer required by Fermentrack (libzmq-dev, libevent-dev, and rabbitmq-server)"
    apt-get remove -y libzmq-dev libevent-dev rabbitmq-server &>> install.log || die

    printinfo "Now installing additional packages required for gravity sensor support (including Tilt)"
    # These packages are required for Bluetooth and Tilt configuration support
    # bluez and python-bluez are for bluetooth support (for Tilt)
    # libcap2-bin is additionally for bluetooth support (for Tilt)
    # python-scipy and python-numpy are for Tilt configuration support
    apt-get install -y bluez python-bluez python-scipy python-numpy libcap2-bin &>>install.log || die

    printinfo "All packages installed successfully."
    echo
}


verifyFreeDiskSpace() {
  printinfo "Verifying free disk space..."
  local required_free_kilobytes=256000
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


setPythonSetcap() {
  printinfo "Enabling python to query bluetooth without being root"

  setcap cap_net_raw+eip /home/fermentrack/venv/bin/python2
}

enableSitePackages() {
  printinfo "Updating the python virtualenv to support global site packages"
  if [ -a /home/fermentrack/venv/lib/python2.7/no-global-site-packages.txt ]; then
    rm /home/fermentrack/venv/lib/python2.7/no-global-site-packages.txt
    printinfo "::: virtualenv updated!"
  else
    printinfo "::: Unable to update virtualenv (it may already have global site packages enabled)"
  fi
}


# Run the upgrade script within Fermentrack
runFermentrackUpgrade() {
  printinfo "Running upgrade.sh from your installation of Fermentrack to finalize the update."
  printinfo "This may take a few minutes during which everything will be silent..."

  if [ -a /home/fermentrack/fermentrack/utils/upgrade.sh ]; then
    cd /home/fermentrack/fermentrack/utils/
    sudo -u fermentrack bash /home/fermentrack/fermentrack/utils/upgrade.sh &>> install.log
  else
    printerror "Could not find /home/fermentrack/fermentrack/utils/upgrade.sh!"
    exit 1
  fi
}


installationReport() {
  MYIP=$(/sbin/ifconfig|egrep -A 1 'eth|wlan'|awk -F"[Bcast:]" '/inet addr/ {print $4}')
  MYIP_TRIM="$(echo -e "${MYIP}" | tr -d '[:space:]')"
  echo "Done installing gravity sensor support!"
  echo "====================================================================================================="
  echo "Review the log above for any errors, otherwise, installation of support is complete!"
  echo
  echo "Next, enable gravity sensor support by logging into Fermentrack, clicking the gear in the upper right,"
  echo "and changing 'Enable gravity support' to 'Yes'."
  echo
  echo " - Fermentrack frontend    : http://${MYIP_TRIM}"
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

echo


verifyInternetConnection
verifyInstallerVersion
verifyInstallLocation
verifyFreeDiskSpace
getAptPackages
setPythonSetcap
enableSitePackages
runFermentrackUpgrade
installationReport
