#!/usr/bin/env bash

DOCKER_IMAGE_TAG="latest"

# Help text
function usage() {
    echo "Usage: $0 [-h] [-i <image>]" 1>&2
    echo "Options:"
    echo "  -h                This help"
    echo "  -i <image>        Docker image tag (defaults to 'latest')"
    exit 1
}

while getopts "hi:" opt; do
  case ${opt} in
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


docker-compose pull
docker image pull "jdbeeler/fermentrack:${DOCKER_IMAGE_TAG}"
docker-compose down

# We're going to prune the networks here as the mdns-reflector launch script is going to try to determine the network
# to bridge based on
docker network prune -f
docker-compose build
# Run migrate here to prevent a race condition with celerybeat
docker-compose run --rm django python manage.py migrate
docker-compose up -d

# Clean up/delete any unused docker images & networks
#docker image prune -f

