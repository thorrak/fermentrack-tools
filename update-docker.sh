#!/usr/bin/env bash

docker image pull jdbeeler/fermentrack
docker-compose -f production.yml down
docker-compose -f production.yml build
docker-compose -f production.yml up -d

# Clean up/delete any unused docker images
docker image prune -f



