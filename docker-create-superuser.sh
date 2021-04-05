#!/usr/bin/env bash

docker-compose stop
docker-compose run --rm django python manage.py createsuperuser
docker-compose up --no-recreate -d
