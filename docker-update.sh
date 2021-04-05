#!/usr/bin/env bash

docker image pull jdbeeler/fermentrack
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

