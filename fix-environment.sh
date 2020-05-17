#!/usr/bin/env bash

# fix-environment.sh - Fix the default environment for default, automated Fermentrack installs

# Recently, I've seen an increasing number of errors that arise from the user's environment not being in a consistent
# state. There are things that can be done to address some of these from within the Fermentrack UI, but a number of
# issues require sudo to correct. This script attempts to address them all, as a one-stop fix.


# Fermentrack is free software, and is distributed under the terms of the MIT license.
# A copy of the MIT license should be included with Fermentrack. If not, a copy can be
# reviewed at <https://opensource.org/licenses/MIT>


green=$(tput setaf 76)
red=$(tput setaf 1)
tan=$(tput setaf 3)
reset=$(tput sgr0)
myPath="$( cd "$( dirname "${BASH_SOURCE[0]}")" && pwd )"

fermentrackUser="fermentrack"
installPath="/home/${fermentrackUser}"



printinfo() {
  printf "::: ${green}%s${reset}\n" "$@"
}


printwarn() {
 printf "${tan}*** WARNING: %s${reset}\n" "$@"
}


printerror() {
 printf "${red}*** ERROR: %s${reset}\n" "$@"
}

die () {
  local st="$?"
  warn "$@"
  exit "$st"
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

# getAptPackages runs apt-get update, and installs the basic packages we need to continue the Fermentrack install
getAptPackages() {
    printinfo "Reinstalling dependencies using apt-get"
    lastUpdate=$(stat -c %Y /var/lib/apt/lists)
    nowTime=$(date +%s)
    if [ $(($nowTime - $lastUpdate)) -gt 604800 ] ; then
        printinfo "Last 'apt-get update' was awhile back. Updating now. (This may take a minute)"
        sudo apt-key update &>> install.log||die
        printinfo "'apt-key update' ran successfully."
        sudo apt-get update &>> install.log||die
        printinfo "'apt-get update' ran successfully."
    fi
    # Installing the nginx stack along with everything we need for circus, etc.
    printinfo "apt is updated - Triggering install of all packages."

    sudo apt-get install -y git-core build-essential nginx redis-server avrdude &>> install.log || die

    sudo apt-get install -y bluez libcap2-bin libbluetooth3 libbluetooth-dev &>> install.log || die

    sudo apt-get install -y python3-venv python3-dev  &>> install.log || die

    printinfo "Apt-packages reinstalled successfully."
    echo
}



fixPermissions() {
  printinfo "Making sure everything is owned by ${fermentrackUser}"
  sudo chown -R ${fermentrackUser}:${fermentrackUser} "$installPath"||die
  # Set sticky bit! nom nom nom
  sudo find "$installPath" -type d -exec chmod g+rwxs {} \;||die
  echo
}

setPythonSetcap() {
  printinfo "Enabling python to query bluetooth without being root"

  PYTHON3_INTERPRETER="$(readlink -e $installPath/venv/bin/python)"
  if [ -a ${PYTHON3_INTERPRETER} ]; then
    sudo setcap cap_net_raw+eip "$PYTHON3_INTERPRETER"
  fi

}


installPython() {
  printinfo "Installing Python 3.7.7"
  printinfo "Warning - This may take several hours to complete, depending on your Pi version"
  printinfo "Let it do its thing. This is important."
  cd ~ || exit
  sudo apt-get update -y
  sudo apt-get install -y build-essential tk-dev libncurses5-dev libncursesw5-dev libreadline6-dev libdb5.3-dev libgdbm-dev libsqlite3-dev libssl-dev libbz2-dev  libexpat1-dev liblzma-dev zlib1g-dev libffi-dev
  sudo apt-get install -y make build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm libncurses5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libzmq5-dev
  wget https://www.python.org/ftp/python/3.7.7/Python-3.7.7.tar.xz
  tar xf Python-3.7.7.tar.xz
  cd Python-3.7.7 || exit
  #./configure --enable-optimizations
  ./configure
  make -j 4
  sudo make altinstall
  cd ..
  rm Python-3.7.7.tar.xz
  sudo apt-get --purge remove tk-dev libncurses5-dev libncursesw5-dev libreadline6-dev libdb5.3-dev libgdbm-dev libsqlite3-dev libssl-dev libbz2-dev libexpat1-dev liblzma-dev zlib1g-dev libffi-dev -y
  sudo apt-get autoremove -y
  sudo apt-get clean

}

createPythonVenv() {
  # Set up virtualenv directory
  printinfo "Creating virtualenv directory..."
  cd "/home/fermentrack" || exit
  sudo -u fermentrack -H rm -rf ~/venv/
  sudo -u fermentrack -H python3.7 -m venv /home/fermentrack/venv

  # Fix the symlinks to only point to Python 3.7
  sudo -u fermentrack -H rm /home/fermentrack/venv/bin/python3
  sudo -u fermentrack -H rm /home/fermentrack/venv/bin/python
  sudo -u fermentrack -H ln -s /home/fermentrack/venv/bin/python3.7 /home/fermentrack/venv/bin/python
  sudo -u fermentrack -H ln -s /home/fermentrack/venv/bin/python3.7 /home/fermentrack/venv/bin/python3

  sudo -u fermentrack -H bash -c "source /home/fermentrack/venv/bin/activate && pip install --no-binary pyzmq pyzmq==19.0.1"
  # I explicitly want to install Circus first, as there are potential clashes with versioning on pyzmq
  sudo -u fermentrack -H bash -c "source /home/fermentrack/venv/bin/activate && /home/fermentrack/venv/bin/python3 -m pip install circus"
  sudo -u fermentrack -H bash -c "source /home/fermentrack/venv/bin/activate && /home/fermentrack/venv/bin/python3 -m pip install numpy scipy pandas"
  echo
}


checkPython37() {
  if command -v python3.7 &> /dev/null; then
    # Python 3.7 is installed. No need to reinstall python manually
    printinfo "Python 3.7 is installed. Continuing."
  else
    installPython

  fi
}




doEverythingRequiringSudo() {
  printinfo "Switching to the Fermentrack user and doing all the other bits..."
exec sudo -u ${fermentrackUser} -H bash << eof
source ~/venv/bin/activate
cd ~/fermentrack

echo "Stopping Circus"
circusctl stop

echo "Upgrading pip"
pip3 install --upgrade pip

echo "Fetching, resetting, and pulling from git..."
git fetch --all
git reset --hard
git pull

echo "Re-installing Python packages from requirements.txt via pip3"
pip3 install --force-reinstall --no-cache-dir -U -r requirements.txt --upgrade

echo "Running manage.py migrate/fix_sqlite_for_django_2/collectstatic..."
python3 manage.py migrate
python3 manage.py fix_sqlite_for_django_2
python3 manage.py collectstatic --noinput >> /dev/null

echo "Quitting Circus"
circusctl quit

echo "Calling updateCronCircus to restart Circus..."
utils/updateCronCircus.sh startifstopped

echo
echo "Done! Exiting."

eof
}


# Run everything
verifyFreeDiskSpace
verifyInternetConnection
getAptPackages
checkPython37
# We're always going to nuke the venv now
createPythonVenv
fixPermissions
setPythonSetcap

# Run the bits requiring sudo (I'd love to break these out...)
doEverythingRequiringSudo
