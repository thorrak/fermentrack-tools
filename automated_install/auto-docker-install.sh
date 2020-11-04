#!/usr/bin/env bash

# auto-install.sh
#
# This script attempts to automatically download fermentrack-tools and use install.sh to install Fermentrack.
# It can be run via curl (See install_curl_command below) which enables the user to install everything with one
# command.

# Fermentrack is free software, and is distributed under the terms of the MIT license.
# A copy of the MIT license should be included with Fermentrack. If not, a copy can be
# reviewed at <https://opensource.org/licenses/MIT>

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

package_name="Fermentrack"
install_curl_url="install.fermentrack.com"
install_script_name="install-docker.sh"
install_curl_command="curl -L $install_curl_url | sudo bash"
tools_name="fermentrack-tools"
tools_repo_url="https://github.com/thorrak/fermentrack-tools.git"

# Set scriptPath to the current script path
unset CDPATH
scriptPath="$( cd "$( dirname "${BASH_SOURCE[0]}")" && pwd )"



#######
#### Error capturing functions - Originally from http://mywiki.wooledge.org/BashFAQ/101
#######
warn() {
  local fmt="$1"
  command shift 2>/dev/null
  echo -e "$fmt\n" "${@}"
  echo -e "\n*** ERROR ERROR ERROR ERROR ERROR ***\n----------------------------------\nSee above lines for error message\nSetup NOT completed\n"
}

die () {
  local st="$?"
  warn "$@"
  exit "$st"
}


#######
#### Compatibility checks & tests
#######
exit_if_pi_zero() {
  # Pi Zero string (armv6l)
  # Linux dockerzero 5.4.51+ #1333 Mon Aug 10 16:38:02 BST 2020 armv6l GNU/Linux
  if uname -a | grep -q 'armv6l'; then
    # I tried supporting armv6l pis, but they're too slow (or otherwise don't work)
    die "This is an armv6l Pi (e.g. Pi Zero, Zero W, or Original RPi) which isn't capable of running Fermentrack. Exiting."
  fi
}

verifyRunAsRoot() {
    # verifyRunAsRoot does two things - First, it checks if the script was run by a root user. Assuming it wasn't,
    # it prompts the user to relaunch as root.

    if [[ ${EUID} -eq 0 ]]; then
        echo "::: This script was launched as root. Continuing installation."
    else
        echo "::: This script was called without root privileges, which are required as it installs and updates several"
        echo "::: packages, and the script it calls within ${tools_name} creates user accounts and updates system"
        echo "::: settings. To continue, this script must launched using the 'sudo' command to run as root. Please check"
        echo "::: the contents of this script (as well as the install script within ${tools_name}) for any concerns with"
        echo "::: this requirement. Please be sure to access this script (and ${tools_name}) from a trusted source."
        echo ":::"
        echo "::: To re-run this script with sudo permissions, type:"
        echo "::: sudo $0"
        exit 1
    fi

}

verifyFreeDiskSpace() {
  echo "::: Verifying free disk space..."
  local required_free_kilobytes=768000
  local existing_free_kilobytes=$(df -Pk | grep -m1 '\/$' | awk '{print $4}')

  # - Unknown free disk space , not a integer
  if ! [[ "${existing_free_kilobytes}" =~ ^([0-9])+$ ]]; then
    echo ":: Unknown free disk space!"
    echo ":: We were unable to determine available free disk space on this system."
    exit 1
  # - Insufficient free disk space
  elif [[ ${existing_free_kilobytes} -lt ${required_free_kilobytes} ]]; then
    echo ":: Insufficient Disk Space!"
    echo ":: Your system appears to be low on disk space. ${package_name} recommends a minimum of $required_free_kilobytes KB."
    echo ":: You only have ${existing_free_kilobytes} KB free."
    echo ":: After freeing up space, run this installation script again. (${install_curl_command})"
    echo "Insufficient free space, exiting..."
    exit 1
  fi
}

#######
#### Installation functions
#######

# getAptPackages runs apt-get update, and installs the basic packages we need to continue the Fermentrack install
# (git-core, build-essential, python-dev, python-virtualenv). The rest can be installed by fermentrack-tools/install.sh
getAptPackages() {
    echo -e "::: Installing dependencies using apt-get"
    lastUpdate=$(stat -c %Y /var/lib/apt/lists)
    nowTime=$(date +%s)
    if [ $(($nowTime - $lastUpdate)) -gt 604800 ] ; then
      echo "::: Last 'apt-get update' was awhile back. Updating now."
      sudo apt-key update &> /dev/null||die
      echo "::: 'apt-key update' ran successfully."
      sudo apt-get update &> /dev/null||die
      echo ":: 'apt-get update' ran successfully."
    fi


    echo "::: apt is updated - installing git-core and build-essential."
    echo "::: (This may take a few minutes during which everything will be silent)"
    sudo apt-get install -y git-core build-essential &> /dev/null || die
    echo ":: All packages installed successfully."
}

handleExistingTools() {
  echo -e ":::: Existing instance of ${tools_name} found at ${scriptPath}/${tools_name}"
  echo -e ":::: Moving to ${scriptPath}/${tools_name}.old/"
  rm -r ${tools_name}.old &> /dev/null
  mv ${tools_name} ${tools_name}.old||die
  echo -e ":::: Moved successfully. Reattempting clone."
  git clone ${tools_repo_url} "${tools_name}" -q &> /dev/null||die
}

cloneFromGit() {
    echo -e "::: Cloning ${tools_name} repo from GitHub into ${scriptPath}/${tools_name}"
    git clone ${tools_repo_url} "${tools_name}" -q &> /dev/null||handleExistingTools
    # TODO - remove this when everything is merged into master
    git checkout docker
    git pull
    echo ":: Repo was cloned successfully."
}


launchInstall() {
    echo "::: This script will now attempt to install ${package_name} using the script that has been created at"
    echo -e "::: ${scriptPath}/${tools_name}/${install_script_name}"
    echo -e "::: If the install script does not complete successfully, please relaunch the script above directly."
    echo -e "::: "
    echo -e "::: Launching ${package_name} installer."
    cd ${tools_name} || exit 1
    # The -n flag makes the install script non-interactive
    sudo bash ./$install_script_name -n
    echo -e "::: Automated installation script has now finished. If installation did not complete successfully please"
    echo -e "::: relaunch the installation script which has been downloaded at:"
    echo -e "::: ${scriptPath}/${tools_name}/${install_script_name}"
}

#######
### Now, for the main event...
#######
echo ""
echo "<<>><<>><<>><<>><<>><<>><<>><<>><<>><<>><<>><<>><<>><<>><<>><<>><<>>"
exit_if_pi_zero
verifyRunAsRoot
verifyFreeDiskSpace
getAptPackages
checkPython37
cloneFromGit
launchInstall
