#!/usr/bin/env bash

docker image pull jdbeeler/fermentrack
docker-compose -f production.yml down
docker-compose -f production.yml build
docker-compose -f production.yml up -d


