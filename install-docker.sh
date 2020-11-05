#!/usr/bin/env bash

# fermentrack-tools is intended for use in setting up installations of Fermentrack on individual "deployed" Raspberry Pis,
# as opposed to being the source for building new Fermentrack Docker images. The main differences between the build in
# fermentrack-tools as opposed to Fermentrack are:

# * fermentrack-tools deployments use the Docker Hub hosted container
# * fermentrack-tools deployments include Sentry links

# DOCKER_DIGEST="sha256:d40df7149a74914ffacf720f39bddf437e1a3a4c70fed820c9ced61f784c3741"

green=$(tput setaf 76)
red=$(tput setaf 1)
tan=$(tput setaf 3)
reset=$(tput sgr0)
myPath="$( cd "$( dirname "${BASH_SOURCE[0]}")" && pwd )"

PORT="80"


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
  printerror "$@"
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

# Check disk space
verifyFreeDiskSpace() {
  printinfo "Verifying free disk space..."
  local required_free_kilobytes=1024000
  local existing_free_kilobytes=$(df -Pk | grep -m1 '\/$' | awk '{print $4}')

  # - Unknown free disk space , not a integer
  if ! [[ "${existing_free_kilobytes}" =~ ^([0-9])+$ ]]; then
    printerror "Unknown free disk space!"
    printerror "We were unable to determine available free disk space on this system."
    exit 1
  # - Insufficient free disk space
  elif [[ ${existing_free_kilobytes} -lt ${required_free_kilobytes} ]]; then
    printerror "Insufficient Disk Space!"
    printerror "Your system appears to be low on disk space. Fermentrack recommends a minimum of $required_free_kilobytes KB."
    printerror "You only have ${existing_free_kilobytes} KB free."
    printerror "Insufficient free space, exiting..."
    exit 1
  fi
  echo
}

updateApt() {
    lastUpdate=$(stat -c %Y /var/lib/apt/lists)
    nowTime=$(date +%s)
    if [ $(($nowTime - $lastUpdate)) -gt 604800 ] ; then
        printinfo "Last 'apt-get update' was awhile back. Updating now. (This may take a minute)"
        apt-key update &>> install.log||die
        printinfo "'apt-key update' ran successfully."
        apt-get update &>> install.log||die
        printinfo "'apt-get update' ran successfully."
    fi
}


install_docker() {
  # Install Git (and anything else we must have on the base system)
  sudo apt-get install git subversion -y
  # Install docker prerequisites
  sudo apt-get install apt-transport-https ca-certificates software-properties-common -y
  # Install docker
  if command -v docker &> /dev/null; then
    # Docker is installed. No need to reinstall.
    printinfo "Docker is already installed. Continuing."
  else
    curl -fsSL get.docker.com -o get-docker.sh && sh get-docker.sh
  fi
  # Install docker-compose
  sudo apt-get install docker-compose -y
  # Add pi to the docker group (for future interaction /w docker)
  if [ "$USER" == "root" ]; then
    # Assume pi (the script is being run as root)
    sudo usermod -aG docker pi
  else
    sudo usermod -aG docker "$USER"
  fi
  # Start the docker service
  sudo systemctl start docker.service
}


get_files_from_main_repo() {
  # Although we're replacing the Dockerfile for the Fermentrack container, everything else is the same. Let's just clone
  # it from GitHub to make life easier.
  printinfo "Downloading required files from GitHub for setup"

  # Delete the files if they exist (we want to overwrite these)
  rm -rf ./compose/

  if [ -f "./production.yml" ]; then
    # TODO - Warn the user on this
    rm production.yml
  fi

  # Download the relevant files from GitHub
  # TODO - Revert this once the files are merged to master (or alternatively dev)
#  svn export https://github.com/thorrak/fermentrack/trunk/compose
#  svn export https://github.com/thorrak/fermentrack/trunk/production.yml
  svn export https://github.com/thorrak/fermentrack/branches/docker/compose
  svn export https://github.com/thorrak/fermentrack/branches/docker/production.yml

  # Last, rewrite production.yml
  if [ -f "./production.yml" ]; then
    sed -i  "s+./.envs/.production/.django+./envs/django+g" production.yml
    sed -i  "s+./.envs/.production/.postgres+./envs/postgres+g" production.yml
    sed -i  "s+./.envs/.production/.postgres+./envs/postgres+g" production.yml
    sed -i  "s+./compose/production/django/Dockerfile+./Dockerfile+g" production.yml
  else
    die "Unable to download production.yml from GitHub"
  fi
}

setup_django_env() {
  SECRET_KEY=$(LC_CTYPE=C tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 50 | head -n 1)
  ADMIN_URL=$(LC_CTYPE=C tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 32 | head -n 1)
#  FLOWER_USER=$(LC_CTYPE=C tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 32 | head -n 1)
#  FLOWER_PASS=$(LC_CTYPE=C tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 64 | head -n 1)

  if [ -f "./envs/django" ]; then
    printinfo "Fermentrack environment configuration already exists at ./envs/django"
  else
    printinfo "Creating Fermentrack environment configuration at ./envs/django"
    mkdir envs
    cp sample_envs/django envs/django
    sed -i "s+{secret_key}+${SECRET_KEY}+g" envs/django
    sed -i "s+{admin_url}+${ADMIN_URL}+g" envs/django
#    sed -i "s+{flower_user}+${FLOWER_USER}+g" envs/django
#    sed -i "s+{flower_password}+${FLOWER_PASS}+g" envs/django
  fi
}

setup_postgres_env() {
  POSTGRES_USER=$(LC_CTYPE=C tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 32 | head -n 1)
  POSTGRES_PASS=$(LC_CTYPE=C tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 64 | head -n 1)

  if [ -f "./envs/postgres" ]; then
    printinfo "Fermentrack Postgres environment configuration already exists at ./envs/postgres"
  else
    printinfo "Creating Fermentrack Postgres environment configuration at ./envs/postgres"
    cp sample_envs/postgres envs/postgres
    sed -i "s+{postgres_user}+${POSTGRES_USER}+g" envs/postgres
    sed -i "s+{postgres_password}+${POSTGRES_PASS}+g" envs/postgres
  fi
}


exit_if_pi_zero() {
  # Pi Zero string (armv6l)
  # Linux dockerzero 5.4.51+ #1333 Mon Aug 10 16:38:02 BST 2020 armv6l GNU/Linux
  if uname -a | grep -q 'armv6l'; then
    # I tried supporting armv6l pis, but they're too slow (or otherwise don't work). Leaving this code here in case I
    # decide to revisit in the future.
    die "This is an armv6l Pi (e.g. Pi Zero, Zero W, or Original RPi) which isn't capable of running Fermentrack. Exiting."
  fi
}


rebuild_fermentrack_containers() {
  printinfo "Downloading, building, and starting Fermentrack containers"
  sudo docker-compose -f production.yml down
  sudo docker-compose -f production.yml build
  sudo docker-compose -f production.yml up -d
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
          return $IP_ADDRESS
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
#  MYIP=$(/sbin/ifconfig|egrep -A 1 'eth|wlan'|awk -F"[Bcast:]" '/inet addr/ {print $4}')
#  MYIP=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')
#  MYIP=$(hostname -I 2>/dev/null|awk '{print $2}')
  # find_ip_address either finds a non-docker IP address that responds with "Fermentrack" in the text when accessed
  # via curl, or it dies. The return value is a string containing the IP.
  find_ip_address
  MYIP=$?

  if [[ $PORT != "80" ]]; then
    URL="http://${MYIP}:${PORT}"
  else
    URL="http://${MYIP}"
  fi

  echo
  echo
  echo "Done installing Fermentrack!"
  echo "================================================================================================="
  echo "Review the log above for any errors, otherwise, your initial environment install is complete!"
  echo
  echo "Fermentrack has been installed into a Docker container along with all its prerequisites."
  echo "To view Fermentrack, enter ${URL} into your web browser."
  echo
  echo "Note - Fermentrack relies on the fermentrack_tools directory to run. Please back up the following"
  echo "       two files to ensure that you do not lose data if you need to reinstall Fermentrack:"
  echo
  echo " - Fermentrack Variables     : ./envs/django"
  echo " - Postgres Variables        : ./envs/postgres"
  echo
  echo " - Fermentrack Address       : ${URL}"
  echo ""
  echo "Happy Brewing!"
  echo ""
}


exit_if_pi_zero
verifyInternetConnection
verifyFreeDiskSpace
install_docker
get_files_from_main_repo
setup_django_env
setup_postgres_env
rebuild_fermentrack_containers
installationReport