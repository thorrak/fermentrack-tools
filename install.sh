#!/usr/bin/env bash

# fermentrack-tools is intended for use in setting up installations of Fermentrack on individual "deployed" Raspberry Pis,
# as opposed to being the source for building new Fermentrack Docker images. The main differences between the build in
# fermentrack-tools as opposed to Fermentrack are:

# * fermentrack-tools deployments use the Docker Hub hosted container
# * fermentrack-tools deployments include Sentry links


green=$(tput setaf 76)
red=$(tput setaf 1)
tan=$(tput setaf 3)
reset=$(tput sgr0)
myPath="$( cd "$( dirname "${BASH_SOURCE[0]}")" && pwd )"


PACKAGE_NAME="Fermentrack"
INTERACTIVE=1
PORT="80"
DOCKER_IMAGE_TAG="latest"



# Help text
function usage() {
    echo "Usage: $0 [-h] [-n] [-p <port_number>] [-i <image>]" 1>&2
    echo "Options:"
    echo "  -h                This help"
    echo "  -n                Run non interactive installation"
    echo "  -p <port_number>  Specify port to access ${PACKAGE_NAME}"
    echo "  -i <image>        Docker image tag (defaults to 'latest')"
    exit 1
}

while getopts "nhp:i:" opt; do
  case ${opt} in
    n)
      INTERACTIVE=0  # Silent/Non-interactive Mode
      ;;
    p)
      PORT=$OPTARG
      ;;
    i)
      DOCKER_IMAGE_TAG=$OPTARG
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
  printf "::: ${green}%s${reset}\n" "$@" >> ./install.log
}


printwarn() {
 printf "${tan}*** WARNING: %s${reset}\n" "$@"
 printf "${tan}*** WARNING: %s${reset}\n" "$@" >> ./install.log
}


printerror() {
 printf "${red}*** ERROR: %s${reset}\n" "$@"
 printf "${red}*** ERROR: %s${reset}\n" "$@" >> ./install.log
}


die () {
  local st="$?"
  printerror "$@"
  exit "$st"
}

exit_if_pi_zero() {
  # Pi Zero string (armv6l)
  # Linux dockerzero 5.4.51+ #1333 Mon Aug 10 16:38:02 BST 2020 armv6l GNU/Linux
  if uname -a | grep -q 'armv6l'; then
    # I tried supporting armv6l pis, but they're too slow (or otherwise don't work). Leaving this code here in case I
    # decide to revisit in the future.
    die "This is an armv6l Pi (e.g. Pi Zero, Zero W, or Original RPi) which isn't capable of running ${PACKAGE_NAME}. Exiting."
  fi
}

# Check for network connection
verifyInternetConnection() {
  printinfo "Checking for Internet connection: "
  wget -q --spider --no-check-certificate github.com &>> ./install.log
  if [ $? -ne 0 ]; then
      echo
      printerror "Could not connect to GitHub. Are you sure you have a working Internet"
      printerror "connection? Installer will exit; it needs to fetch code from GitHub."
      exit 1
  fi
  printinfo "Internet connection Success!"
}

# Check disk space
verifyFreeDiskSpace() {
  printinfo "Verifying free disk space..."
  local required_free_gigabytes=2
  local required_free_kilobytes=$(( required_free_gigabytes*1024000 ))
  local existing_free_kilobytes=$(df -Pk | grep -m1 '\/$' | awk '{print $4}')

  # - Unknown free disk space , not a integer
  if ! [[ "${existing_free_kilobytes}" =~ ^([0-9])+$ ]]; then
    printwarn ":: Unknown free disk space!"
    die "We were unable to determine available free disk space on this system."
  # - Insufficient free disk space
  elif [[ ${existing_free_kilobytes} -lt ${required_free_kilobytes} ]]; then
    printwarn "Insufficient Disk Space!"
    printinfo "Your system appears to be low on disk space. ${PACKAGE_NAME} recommends a minimum of $required_free_gigabytes GB."
    printinfo "After freeing up space, run this installation script again. (${install_curl_command})"
    die "Insufficient free space, exiting..."
  fi
  printinfo "Sufficient free disk space is available"
}


docker_compose_down() {
  # docker_compose_down is a way for us to nuke an existing docker stack -JUST IN CASE-.
  if command -v docker-compose &> /dev/null; then
    # Docker compose exists
    if [ -f "./docker-compose.yml" ]; then
        # The docker-compose file also exists, so we can attempt to shut down the docker-compose stack
      if [ -f "./envs/django" ]; then
        # If the environment file exists, then we almost certainly have run the installer before. Give the user a chance
        # to Ctrl+C out
        printwarn "Existing run of this installer detected."
        printinfo "This script will now attempt to shut down any previous installation of ${PACKAGE_NAME}"
        printinfo "before proceeding. To cancel this, press Ctrl+C in the next 5 seconds."
        sleep 5s
      else
        printinfo "This script will now attempt to shut down any previous installation of ${PACKAGE_NAME}"
        printinfo "before proceeding."
      fi
      printinfo "Shutting down previous installation..."
      docker-compose -f docker-compose.yml down &>> install.log
      printinfo "Previous installation shut down. Continuing with install."
    fi
  fi
}


check_for_web_service_port() {
  # Allow the user to set the default port for the web service.

  # TODO - Don't show this if the user selected the port as a command line argument
  if [[ ${INTERACTIVE} -eq 1 ]]; then  # Don't ask questions if we're running in noninteractive mode
    printinfo "The default port for ${PACKAGE_NAME} to run on is port 80 (which is standard"
    printinfo "for most websites). If you have another service currently running on port 80"
    printinfo "then this install will likely fail unless another port is selected."
    echo
    read -p "What port would you like to access ${PACKAGE_NAME} on? [${PORT}]: " PORT_SEL
    if [ -z "${PORT_SEL}" ]; then
      PORT="${PORT}"
    else
      case "${PORT_SEL}" in
        y | Y | yes | YES| Yes )
            PORT="${PORT}";; # accept default when y/yes is answered
        * )
            PORT="${PORT_SEL}"
            ;;
      esac
    fi
  fi

  # Make sure the port number we were provided is valid (hijacking nc's stderr for this)
  local INVALID_COUNT=$(nc -z 127.0.0.1 "${PORT}" 2> >(grep -m 1 -c "invalid"))
  if [ "$INVALID_COUNT" == "1" ] ; then
    die "'${PORT}' is not a valid port number"
  fi

  # Then make sure the port isn't currently occupied
  if nc -z 127.0.0.1 "${PORT}" ; then
    printwarn "Port ${PORT} is currently in use."
    printinfo "You probably want to stop the installation here and either select a"
    printinfo "new port or stop the service currently occupying port ${PORT}."
    printwarn "Installation will continue with port ${PORT} in 10 seconds unless you press Ctrl+C now."
    sleep 10s
  else
    printinfo "${PORT} is a valid port for installation. Continuing."
  fi
}

check_for_other_services_ports() {
  # Since we're (currently) running in net=host mode, all of our services (including postgres & redis) need their
  # ports to be free.

  # TODO - Properly interpret the service URLs set in the environment files rather than just hardcoding defaults here
  # Redis default port is 6379
  if nc -z 127.0.0.1 "6379" ; then
    die "Port 6379 is required by Redis, but is currently in use. Installation cannot continue."
  fi

  # Postgres default port is 5432
  if nc -z 127.0.0.1 "5432" ; then
    die "Port 5432 is required by Postgres, but is currently in use. Installation cannot continue."
  fi


}

updateApt() {
    lastUpdate=$(stat -c %Y /var/lib/apt/lists)
    nowTime=$(date +%s)
    if [ $(($nowTime - $lastUpdate)) -gt 604800 ] ; then
        printinfo "Last 'apt-get update' was awhile back. Updating now. (This may take a minute)"
        sudo apt-get update &>> install.log||die "Unable to run apt-get update"
        printinfo "'apt-get update' ran successfully."
    fi
}


install_docker() {
  # Install Git (and anything else we must have on the base system)
  printinfo "Checking/installing Docker prerequisites using apt-get"
  sudo apt-get install git subversion -y  &>> install.log||die "Unable to install subversion"
  sudo apt-get install ncat -y  &>> install.log||die "Unable to install ncat"
  # Install docker prerequisites
  sudo apt-get install apt-transport-https ca-certificates software-properties-common -y  &>> install.log||die "Unable to install docker prerequisites"
  # Install docker
  if command -v docker &> /dev/null; then
    # Docker is installed. No need to reinstall.
    printinfo "Docker is already installed. Continuing."
  else
    printinfo "Docker is not installed. Installing."
    curl -fsSL get.docker.com -o get-docker.sh && sh get-docker.sh  &>> install.log
  fi
  # Install docker-compose
  if command -v docker-compose &> /dev/null; then
    # Docker is installed. No need to reinstall.
    printinfo "Docker-compose is already installed. Continuing."
  else
    printinfo "Docker-compose is not installed. Installing."
    sudo apt-get install docker-compose -y  &>> install.log||die "Unable to install docker-compose"
  fi
  # Add pi to the docker group (for future interaction /w docker)
  if [ "$USER" == "root" ]; then
    printinfo "Script is run as root - no need to add to docker group."
  else
    if id -nG "$USER" | grep -qw "docker"; then
      printinfo "${USER} already belongs to the 'docker' group"
    else
      printinfo "Adding ${USER} to the 'docker' group."
      sudo usermod -aG docker "$USER"  &>> install.log
    fi
  fi
  # Start the docker service
  sudo systemctl start docker.service  &>> install.log

  # At this point, docker should be installed and running, and the current user should have access. Check if the current
  # user can run docker ps - if he/she can, then we can proceed.
  if sg docker -c "docker ps" &> /dev/null; then
    printinfo "Able to access docker - Proceeding."
  else
    printerror "Unable to access docker. Try logging out and back in and re-running the installer. If that doesn't work, try restarting your pi."
    printerror "If that still doesn't work, try running sudo chmod 666 /var/run/docker.sock"
    printerror "Be aware, though, that will open docker access to all logged in user of this device. Only run that command if you are the only user."
    die "Unable to access Docker"
  fi
}


get_files_from_main_repo() {
  # Although we're replacing the Dockerfile for the Fermentrack container, everything else is the same. Let's just clone
  # it from GitHub to make life easier.
  printinfo "Downloading required files from GitHub for setup"

  # Delete the docker compose files if they exist (we want to overwrite these)
  rm -rf ./compose/
  if [ -f "./docker-compose.yml" ]; then
    # TODO - Warn the user on this
    rm docker-compose.yml
  fi

  # Download the relevant files from GitHub
  svn export https://github.com/thorrak/fermentrack/branches/master/compose &>> install.log

  cp sample.docker-compose.yml docker-compose.yml
}

setup_django_env() {
  SECRET_KEY=$(LC_CTYPE=C tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 50 | head -n 1)
  ADMIN_URL=$(LC_CTYPE=C tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 32 | head -n 1)
#  FLOWER_USER=$(LC_CTYPE=C tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 32 | head -n 1)
#  FLOWER_PASS=$(LC_CTYPE=C tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 64 | head -n 1)

  if [ -f "./envs/django" ]; then
    printinfo "${PACKAGE_NAME} environment configuration already exists at ./envs/django"
  else
    printinfo "Creating ${PACKAGE_NAME} environment configuration at ./envs/django"
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
    printinfo "${PACKAGE_NAME} Postgres environment configuration already exists at ./envs/postgres"
  else
    printinfo "Creating ${PACKAGE_NAME} Postgres environment configuration at ./envs/postgres"
    cp sample_envs/postgres envs/postgres
    sed -i "s+{postgres_user}+${POSTGRES_USER}+g" envs/postgres
    sed -i "s+{postgres_password}+${POSTGRES_PASS}+g" envs/postgres
  fi
}

setup_tiltbridge_jr_env() {
  if [ -f "./envs/tiltbridge-jr" ]; then
    printinfo "${PACKAGE_NAME} TiltBridge Junior environment configuration already exists at ./envs/tiltbridge-jr"
  else
    printinfo "Creating ${PACKAGE_NAME} TiltBridge Junior environment configuration at ./envs/tiltbridge-jr"
    cp sample_envs/tiltbridge-jr envs/tiltbridge-jr
    sed -i "s+FERMENTRACK_LEGACY_TARGET_ENABLED=false+FERMENTRACK_LEGACY_TARGET_ENABLED=true+g" envs/tiltbridge-jr
  fi
}

#setup_mdns_repeater_env() {
#  # TODO - Do something to detect the external interface here
#
#  if [ -f "./envs/mdns-repeater" ]; then
#    printinfo "KegScreen mdns-repeater environment configuration already exists at ./envs/mdns-repeater"
#  else
#    printinfo "Creating KegScreen mdns-repeater environment configuration at ./envs/mdns-repeater"
#    cp sample_envs/mdns-repeater envs/mdns-repeater
#  fi
#}

set_web_services_port() {
  # Rewrite the nginx config file (necessary since we're now using net=host)
  if [ -f "./compose/production/nginx/nginx.conf" ]; then
    sed -i "s+:80+:${PORT}+g" ./compose/production/nginx/nginx.conf
  fi

  # Update the port mapping in docker-compose.yml (ignored if we're using net=host)
  sed -i  "s+80:80+${PORT}:80+g" docker-compose.yml
}

set_docker_image_tag() {
  # Update the image tag in docker-compose.yml
  sed -i  "s+fermentrack:latest+fermentrack:${DOCKER_IMAGE_TAG}+g" docker-compose.yml
  if [ "$DOCKER_IMAGE_TAG" != "latest" ]; then
    if [ -f "./compose/production/nginx/nginx.conf" ]; then
      sed -i "s+:8123+:5000+g" ./compose/production/nginx/nginx.conf
    fi
  fi
}

rebuild_containers() {
  printinfo "Downloading, building, and starting ${PACKAGE_NAME} containers"
  # Running sg docker since if we just added the user to the docker group his/her shell won't reflect the new membership
  sg docker -c "./docker-update.sh -i ${DOCKER_IMAGE_TAG}"
}


find_ip_address() {
  # find_ip_address either finds a non-docker IP address that responds with "Fermentrack" in the text when accessed
  # via curl, or it dies. We can use this to pick out the proper, externally-routable IP address we can use to
  # access the application.

  IP_ADDRESSES=($(hostname -I 2>/dev/null))
  printinfo "Waiting for ${PACKAGE_NAME} install to initialize and become responsive."
  printinfo "${PACKAGE_NAME} may take up to 3 minutes to first boot as the database is being initialized."

  for i in {1..90}; do
    for IP_ADDRESS in "${IP_ADDRESSES[@]}"
    do
      if [[ $IP_ADDRESS != "172."* ]]; then
        FT_COUNT=$(curl -L "http://${IP_ADDRESS}:${PORT}" 2>/dev/null | grep -m 1 -c ${PACKAGE_NAME})
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
  die "Unable to find an initialized, responsive instance of ${PACKAGE_NAME}"
}


installationReport() {
  # Call find_ip_address to locate the install once it spins up
  find_ip_address

  if [[ $PORT != "80" ]]; then
    URL="http://${IP_ADDRESS}:${PORT}"
  else
    URL="http://${IP_ADDRESS}"
  fi

  echo
  echo
  printinfo "Done installing ${PACKAGE_NAME}!"
  echo "================================================================================"
  echo "Review the log above for any errors, otherwise, your initial environment install"
  echo "is complete!"
  echo
  echo "${PACKAGE_NAME} has been installed into a Docker container. To view ${PACKAGE_NAME}"
  echo "enter ${URL} into your web browser."
  echo
  echo "Note - ${PACKAGE_NAME} relies on the fermentrack-tools directory to run. Please "
  echo "       back up the following files to ensure that you do not lose data if you"
  echo "       need to reinstall ${PACKAGE_NAME}:"
  echo
  echo " - ${PACKAGE_NAME} Variables     : ./envs/django"
  echo " - Postgres Variables        : ./envs/postgres"
  echo
  echo " - ${PACKAGE_NAME} Address       : ${URL}"
  echo ""
  echo "Happy Brewing!"
  echo ""
}


exit_if_pi_zero
verifyInternetConnection
verifyFreeDiskSpace
updateApt
install_docker
get_files_from_main_repo
docker_compose_down
check_for_web_service_port
check_for_other_services_ports
setup_django_env
setup_postgres_env
setup_tiltbridge_jr_env
set_web_services_port
set_docker_image_tag
rebuild_containers
installationReport
