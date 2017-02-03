#!/bin/bash



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


############
### Init
###########

# Make sure only root can run our script
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root: sudo ./install-esp8266.sh" 1>&2
   exit 1
fi

############
### Functions to catch/display errors during setup
############
warn() {
  local fmt="$1"
  command shift 2>/dev/null
  echo -e "$fmt\n" "${@}"
  echo -e "\n*** ERROR ERROR ERROR ERROR ERROR ***\n----------------------------------\nSee above lines for error message\nSetup NOT completed\n"
}

die () {
  local st="$?"
  warn "$@"
  exit "$st"
}

############
### Create install log file
############
exec > >(tee -i install.esp8266.log)
exec 2>&1

############
### Check for network connection
###########
echo -e "\nChecking for Internet connection..."
ping -c 3 github.com &> /dev/null
if [ $? -ne 0 ]; then
    echo "------------------------------------"
    echo "Could not ping github.com. Are you sure you have a working Internet connection?"
    echo "Installer will exit, because it needs to fetch code from github.com"
    exit 1
fi
echo -e "Success!\n"

############
### Check whether installer is up-to-date
############
echo -e "\nChecking whether this script is up to date...\n"
unset CDPATH
myPath="$( cd "$( dirname "${BASH_SOURCE[0]}")" && pwd )"
bash "$myPath"/update-tools-repo.sh
if [ $? -ne 0 ]; then
    echo "The update script was not up-to-date, but it should have been updated. Please re-run install.sh."
    exit 1
fi


############
### Install required packages
############
echo -e "\n***** Installing/updating required packages... *****\n"
lastUpdate=$(stat -c %Y /var/lib/apt/lists)
nowTime=$(date +%s)
if [ $(($nowTime - $lastUpdate)) -gt 604800 ] ; then
    echo "last apt-get update was over a week ago. Running apt-get update before updating dependencies"
    sudo apt-get update||die
fi
echo -e "\n***** Installing/updating required python packages via pip... *****\n"
sudo pip install esptool --upgrade
echo -e "\n***** Done processing ESP8266 dependencies *****\n"


############
### Setup questions
############

free_percentage=$(df /home | grep -vE '^Filesystem|tmpfs|cdrom|none' | awk '{ print $5 }')
free=$(df /home | grep -vE '^Filesystem|tmpfs|cdrom|none' | awk '{ print $4 }')
free_readable=$(df -H /home | grep -vE '^Filesystem|tmpfs|cdrom|none' | awk '{ print $4 }')

if [ "$free" -le "25000" ]; then
    echo -e "\nDisk usage is $free_percentage, free disk space is $free_readable"
    echo "Not enough space to continue setup. Installing this software requires at least 25mb free space"
    echo "Did you forget to expand your root partition? To do so run 'sudo raspi-config', expand your root partition and reboot"
    exit 1
else
    echo -e "\nDisk usage is $free_percentage, free disk space is $free_readable. Enough to install this software\n"
fi



############
### Now for the install!
############
echo -e "\n*** This script will first ask you where to download the ESP8266 firmware"
echo "Hitting 'enter' will accept the default option in [brackets] (recommended)."

echo -e "\nAny data in the following location will be ERASED during install!"
read -p "Where would you like to download the ESP8266 firmware? [/home/brewpi/esp8266]: " installPath
if [ -z "$installPath" ]; then
  installPath="/home/brewpi/esp8266"
else
  case "$installPath" in
    y | Y | yes | YES| Yes )
        installPath="/home/brewpi/esp8266";; # accept default when y/yes is answered
    * )
        ;;
  esac
fi
echo "Installing script in $installPath";

if [ -d "$installPath" ]; then
  if [ "$(ls -A ${installPath})" ]; then
    read -p "Install directory is NOT empty, are you SURE you want to use this path? [y/N] " yn
    case "$yn" in
        y | Y | yes | YES| Yes ) echo "Ok, we warned you!";;
        * ) exit;;
    esac
  fi
else
  if [ "$installPath" != "/home/brewpi/esp8266" ]; then
    read -p "This path does not exist, would you like to create it? [Y/n] " yn
    if [ -z "$yn" ]; then
      yn="y"
    fi
    case "$yn" in
        y | Y | yes | YES| Yes ) echo "Creating directory..."; mkdir -p "$installPath";;
        * ) echo "Aborting..."; exit;;
    esac
  fi
fi



############
### Clone ESP8266 firmware repository
############
echo -e "\n***** Downloading most recent ESP8266 firmware... *****"
sudo -u brewpi git clone https://github.com/thorrak/brewpi-esp8266 "$installPath"||die
cd "$installPath"

firmwareName="brewpi-esp8266.v0.1.wifi.bin"


echo -e "Done downloading firmware!"

echo -e "\n* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *"
echo -e "Review the log above for any errors, otherwise, your software download and environment setup is complete!"
echo -e "\nThe next step is to actually flash the firmware to your device. Unhook any other USB-to-serial bridges, hook the ESP8266 device up via a USB cable to your Raspberry Pi, then do the following:"
echo -e "\nsudo esptool.py --port /dev/ttyUSB0 write_flash -fm=dio -fs=32m 0x00000 $installPath/bin/$firmwareName"

# TODO - Add option to automatically run the above command




