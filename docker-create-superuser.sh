#!/usr/bin/env bash

if docker compose version >/dev/null 2>&1; then
  DOCKER_COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  DOCKER_COMPOSE="docker-compose"
else
  echo "Error: Neither 'docker compose' nor 'docker-compose' was found. Please install Docker Compose and try again."
  exit 1
fi

$DOCKER_COMPOSE stop
$DOCKER_COMPOSE run --rm django python manage.py createsuperuser
$DOCKER_COMPOSE up --no-recreate -d
