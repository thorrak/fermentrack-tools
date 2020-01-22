#!/usr/bin/env bash

# force-pip-install.sh - Forces an installation of pip within a specified virtualenv

# This script is an attempt to fix a bug where installations of certain python packages (including circus) fail -
# presumably because the version of pip that is available has been heavily modified. This script forces an installation
# of pip into a virtualenv so that any subsequent packages are installed with that (hopefully intact!) version of pip.


# Fermentrack is free software, and is distributed under the terms of the MIT license.
# A copy of the MIT license should be included with Fermentrack. If not, a copy can be
# reviewed at <https://opensource.org/licenses/MIT>


green=$(tput setaf 76)
red=$(tput setaf 1)
tan=$(tput setaf 3)
reset=$(tput sgr0)
myPath="$( cd "$( dirname "${BASH_SOURCE[0]}")" && pwd )"

############## Command Line Options Parser

# Help text
function usage() {
    echo "Usage: $0 -p <venv_activate_path>" 1>&2
    echo "Options:"
    echo "  -h                         This help"
    echo "  -p <venv_activate_path>    Path to the activate script for the virtualenv"
    exit 1
}

while getopts "p:" opt; do
  case ${opt} in
    p)
      activate_path=$OPTARG
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


# All this script does is launch the virtualenv & then force an installation of pip. It lives in its own script so
# we can easily call it with 'sudo'.
source ${activate_path}
pip install -U --force-reinstall pip
pip install -U pip
