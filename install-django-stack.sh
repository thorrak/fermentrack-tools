#!/usr/bin/env bash




# Copyright 2013 BrewPi
# This file is part of BrewPi.

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

########################
### This script assumes a clean Raspbian install.
### Freeder, v1.0, Aug 2013
### Elco, Oct 2013
### Using a custom 'die' function shamelessly stolen from http://mywiki.wooledge.org/BashFAQ/101
### Using ideas even more shamelessly stolen from Elco and mdma. Thanks guys!
########################


# For brewpi-django, the process will work like this:
# 1. Install the system-wide packages (nginx, etc.)
# 2. Confirm the install settings
# 3. Add the users
# 4. Clone the brewpi-django repo
# 5. Run the brewpi-django upgrade script
# 6. Copy the nginx configuration file & restart nginx


############
### Init
###########

# Make sure only root can run our script
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root: sudo ./install.sh" 1>&2
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
exec > >(tee -i install.log)
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
# Installing the nginx stack along with everything we need for circus, etc.
sudo apt-get install -y git-core build-essential python-dev python-pip pastebinit nginx libzmq-dev libevent-dev python-virtualenv || die

echo -e "\n***** Installing/updating required python packages via pip... *****\n"
# TODO - Change the following line to utilize requirements.txt files
sudo pip install pyserial psutil simplejson configobj gitpython zeroconf --upgrade
echo -e "\n***** Done processing non-pip BrewPi dependencies *****\n"


############
### Setup questions
############

free_percentage=$(df /home | grep -vE '^Filesystem|tmpfs|cdrom|none' | awk '{ print $5 }')
free=$(df /home | grep -vE '^Filesystem|tmpfs|cdrom|none' | awk '{ print $4 }')
free_readable=$(df -H /home | grep -vE '^Filesystem|tmpfs|cdrom|none' | awk '{ print $4 }')

if [ "$free" -le "512000" ]; then
    echo -e "\nDisk usage is $free_percentage, free disk space is $free_readable"
    echo "Not enough space to continue setup. Installing BrewPi requires at least 512mb free space"
    echo "Did you forget to expand your root partition? To do so run 'sudo raspi-config', expand your root partition and reboot"
    exit 1
else
    echo -e "\nDisk usage is $free_percentage, free disk space is $free_readable. Enough to install BrewPi\n"
fi


echo "To accept the default answer, just press Enter."
echo "The default is capitalized in a Yes/No question: [Y/n]"
echo "or shown between brackets for other questions: [default]"

date=$(date)
read -p "The time is currently set to $date. Is this correct? [Y/n]" choice
case "$choice" in
  n | N | no | NO | No )
    dpkg-reconfigure tzdata;;
  * )
esac


############
### Now for the install!
############
echo -e "\n*** All scripts associated with BrewPi & BrewPi-Django are now installed to a user's home directory"
echo "Hitting 'enter' will accept the default option in [brackets] (recommended)."

echo -e "\nAny data in the user's home directory may be ERASED during install!"
read -p "What user would you like to install BrewPi under? [brewpi]: " brewPiUser
if [ -z "$brewPiUser" ]; then
  brewPiUser="brewpi"
else
  case "$brewPiUser" in
    y | Y | yes | YES| Yes )
        brewPiUser="brewpi";; # accept default when y/yes is answered
    * )
        ;;
  esac
fi
installPath="/home/$brewPiUser"
echo "Configuring under user $brewPiUser";
echo "Configuring in directory $installPath";

if [ -d "$installPath" ]; then
  if [ "$(ls -A ${installPath})" ]; then
    read -p "Install directory is NOT empty, are you SURE you want to use this path? [y/N] " yn
    case "$yn" in
        y | Y | yes | YES| Yes ) echo "Ok, we warned you!";;
        * ) exit;;
    esac
  fi
else
  if [ "$installPath" != "/home/brewpi" ]; then
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
### Create/configure user accounts
############
echo -e "\n***** Creating and configuring user accounts... *****"

if id -u $brewPiUser >/dev/null 2>&1; then
  echo "User '$brewPiUser' already exists, skipping..."
else
  useradd -G dialout $brewPiUser||die
  # TODO - Is this the right thing to do??
  echo -e "$brewPiUser\n$brewPiUser\n" | passwd brewpi||die
fi

# add pi user to brewpi and www-data group
if id -u pi >/dev/null 2>&1; then
  usermod -a -G www-data pi||die
  usermod -a -G brewpi pi||die
fi



echo -e "\n***** Checking install directories *****"

if [ -d "$installPath" ]; then
  echo "$installPath already exists"
else
  mkdir -p "$installPath"
fi

dirName=$(date +%F-%k:%M:%S)
if [ "$(ls -A ${installPath})" ]; then
  echo "Script install directory is NOT empty, backing up to this users home dir and then deleting contents..."
    if ! [ -a ~/brewpi-backup/ ]; then
      mkdir -p ~/brewpi-backup
    fi
    mkdir -p ~/brewpi-backup/"$dirName"
    cp -R "$installPath" ~/brewpi-backup/"$dirName"/||die
    rm -rf "$installPath"/*||die
    find "$installPath"/ -name '.*' | xargs rm -rf||die
fi

chown -R brewpi:brewpi "$installPath"||die

############
### Set sticky bit! nom nom nom
############
find "$installPath" -type d -exec chmod g+rwxs {} \;||die


############
### Clone BrewPi repositories
############
echo -e "\n***** Downloading most recent BrewPi-Django codebase... *****"
cd "$installPath"
# Using the /thorrak/ repo instead to support esp8266
sudo -u brewpi git clone https://github.com/thorrak/brewpi-django.git "$installPath/brewpi-django"||die


# TODO - Update or remove the cron & fix permissions scripts
############
### Fix permissions
############
echo -e "\n***** Running fixPermissions.sh from the script repo. *****"
if [ -a "$installPath"/utils/fixPermissions.sh ]; then
   bash "$installPath"/utils/fixPermissions.sh
else
   echo "ERROR: Could not find fixPermissions.sh!"
fi

############
### Install CRON job
############
echo -e "\n***** Running updateCron.sh from the script repo. *****"
if [ -a "$installPath"/utils/updateCron.sh ]; then
   bash "$installPath"/utils/updateCron.sh
else
   echo "ERROR: Could not find updateCron.sh!"
fi

############
### Check for insecure SSH key
############
defaultKey="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDLNC9E7YjW0Q9btd9aUoAg++/wa06LtBMc1eGPTdu29t89+4onZk1gPGzDYMagHnuBjgBFr4BsZHtng6uCRw8fIftgWrwXxB6ozhD9TM515U9piGsA6H2zlYTlNW99UXLZVUlQzw+OzALOyqeVxhi/FAJzAI9jPLGLpLITeMv8V580g1oPZskuMbnE+oIogdY2TO9e55BWYvaXcfUFQAjF+C02Oo0BFrnkmaNU8v3qBsfQmldsI60+ZaOSnZ0Hkla3b6AnclTYeSQHx5YqiLIFp0e8A1ACfy9vH0qtqq+MchCwDckWrNxzLApOrfwdF4CSMix5RKt9AF+6HOpuI8ZX root@raspberrypi"

if grep -q "$defaultKey" /etc/ssh/ssh_host_rsa_key.pub; then
  echo "Replacing default SSH keys. You will need to remove the previous key from known hosts on any clients that have previously connected to this rpi."
  if rm -f /etc/ssh/ssh_host_* && dpkg-reconfigure openssh-server; then
     echo "Default SSH keys replaced."
  else
    echo "ERROR - Unable to replace SSH key. You probably want to take the time to do this on your own."
  fi
fi

echo -e "Done installing BrewPi!"

echo -e "\n* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *"
echo -e "Review the log above for any errors, otherwise, your initial environment install is complete!"
echo -e "\nYou are currently using the password 'brewpi' for the brewpi user. If you wish to change this, type 'sudo passwd brewpi' now, and follow the prompt"
echo -e "\nTo view your BrewPi web interface, enter http://`/sbin/ifconfig|egrep -A 1 'eth|wlan'|awk -F"[Bcast:]" '/inet addr/ {print $4}'` into your web browser"
echo -e "\nHappy Brewing!"



