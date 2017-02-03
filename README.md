brewpi-tools
============

Various tools to setup/update/configure BrewPi

* install.sh - This is a stand-alone bash script that will install BrewPi onto a Raspbian distro

* updater.py - This is a python script that will check for any updates to BrewPi and, upon request, install them to your Pi

* install-esp8266.sh - This is a stand-alone bash script that will download the necessary files for setting up an ESP8266 into this directory.

###Note from Thorrak
This script is almost entirely the one originally designed by Elco/Freeder. The only meaningful changes are the shift to use my brewpi-script repo (for WiFi & ESP8266 support) and the addition of a script to download the necessary tools for installing firmware on an ESP8266 board.