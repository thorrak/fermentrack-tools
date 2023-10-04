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
install_script_name="install.sh"
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
    warn "This is an armv6l Pi (e.g. Pi Zero, Zero W, or Original RPi) which may not provide a good user experience."
    warn "The installation script will download, but you will need to manually run it with a flag acknowleding that you're running on unsupported hardware."
  fi
}

verifyRunAsRoot() {
    # verifyRunAsRoot does two things - First, it checks if the script was run by a root user. Assuming it wasn't,
    # it prompts the user to relaunch as root.

  echo ":: Checking user"

    if [[ ${EUID} -eq 0 ]]; then
        echo "::: This script was launched as root. Although this used to be the recommended installation method,"
        echo "::: installs now recommend being launched under the standard user (generally 'pi' for Raspberry Pi"
        echo "::: installations). If you wish to cancel this installation and relaunch as a different user, press"
        echo "::: Ctrl+C now. If you wish to continue to install as 'root' wait 10 seconds and the script will"
        echo "::: continue."
        sleep 10s
    else
        echo "::: This script was called without root privileges, which is recommended. The script will, however,"
        echo "::: need root privileges periodically in order to install certain packages. Please be ready to"
        echo "::: enter your password if prompted to allow installation to continue."
        echo ":::"
    fi

}

verifyFreeDiskSpace() {
  echo ":: Verifying free disk space..."
  local required_free_gigabytes=2
  local required_free_kilobytes=$(( required_free_gigabytes*1024000 ))
  local existing_free_kilobytes=$(df -Pk | grep -m1 '\/$' | awk '{print $4}')

  # - Unknown free disk space , not a integer
  if ! [[ "${existing_free_kilobytes}" =~ ^([0-9])+$ ]]; then
    echo "::: Unknown free disk space!"
    echo ":::: We were unable to determine available free disk space on this system."
    exit 1
  # - Insufficient free disk space
  elif [[ ${existing_free_kilobytes} -lt ${required_free_kilobytes} ]]; then
    echo "::: Insufficient Disk Space!"
    echo ":::: Your system appears to be low on disk space. ${package_name} recommends a minimum of $required_free_gigabytes GB."
    echo ":::: After freeing up space, run this installation script again. (${install_curl_command})"
    echo "Insufficient free space, exiting..."
    exit 1
  fi

  echo "::: Sufficent free space for installation"
}

#######
#### Installation functions
#######

# getAptPackages runs apt-get update, and installs the basic packages we need to continue the Fermentrack install
# (git and build-essential). The rest can be installed by fermentrack-tools/install.sh
getAptPackages() {
    echo -e ":: Installing dependencies using apt-get"
    lastUpdate=$(stat -c %Y /var/lib/apt/lists)
    nowTime=$(date +%s)
    if [ $(($nowTime - $lastUpdate)) -gt 604800 ] ; then
      echo "::: Last 'apt-get update' was awhile back. Updating now."
      sudo apt-get update &> /dev/null||die
      echo ":::: 'apt-get update' ran successfully."
    fi

    echo "::: installing git and build-essential."
    echo "::: (This may take a few minutes during which everything will be silent)"
    sudo apt-get install -y git build-essential &> /dev/null || die
    echo ":::: All packages installed successfully."
}


cloneFromGit() {
    echo -e ":: Cloning ${tools_name} repo from GitHub into ${scriptPath}/${tools_name}"

    if [ -f "./${tools_name}/$install_script_name" ]; then
      echo -e "::: Existing instance of ${tools_name} found at ${scriptPath}/${tools_name}"
      echo -e "::: Pulling from Git rather than re-cloning"
      cd ${tools_name} || die "Unable to cd to $tools_name"
      git fetch &> /dev/null
      git pull &> /dev/null
      cd ..
      echo -e ":::: Pull from Git was successful"
    else
      git clone ${tools_repo_url} "${tools_name}" -q &> /dev/null||die "Unable to clone from GitHub"
      echo "::: Repo was cloned successfully."
    fi


}


launchInstall() {
    echo -e ":: This script will now attempt to install ${package_name} using the script that has been created at"
    echo -e "::: ${scriptPath}/${tools_name}/${install_script_name}"
    echo -e "::: If the install script does not complete successfully, please relaunch the script above directly."
    echo -e "::: "
    echo -e ":::: Launching ${package_name} installer."
    cd ${tools_name} || die "Unable to launch ${install_script_name}!"
    # The -n flag makes the install script non-interactive
    #bash ./$install_script_name -n
    exec "./${install_script_name}"
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
cloneFromGit
launchInstall
