#!/usr/bin/env bash

docker image pull jdbeeler/fermentrack
docker-compose -f production.yml down

# We're going to prune the networks here as the mdns-reflector launch script is going to try to determine the network
# to bridge based on
docker network prune -f
docker-compose -f production.yml build
docker-compose -f production.yml up -d

# Clean up/delete any unused docker images & networks
docker image prune -f

