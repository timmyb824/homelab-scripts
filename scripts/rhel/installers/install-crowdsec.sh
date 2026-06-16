#!/bin/sh
#
# Inspired from packagecloud installation scripts
#
# #MIT License
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# Crowdsec repositories installation script
#
# This script:
# - Requires `root` or `sudo` privileges to run
# - Attempts to detect your Linux distribution and version and configure your
#   package management system for you.
# - Installs dependencies and recommendations without asking for confirmation.
# - Is POSIX compliant and can be run using bash or any POSIX-compliant shell


unknown_os() {
    echo "Unfortunately, your operating system distribution and version are not supported by this script."
    echo
    echo "You can override the OS detection by setting os= and dist= prior to running this script."
    echo "You can find a list of supported OSes and distributions on our website: https://packagecloud.io/docs#os_distro_version"
    echo
    echo "For example, to force Ubuntu Trusty: os=ubuntu dist=trusty ./script.sh"
    echo
    echo "Please file an issue at https://github.com/crowdsecurity/crowdsec"
    exit 1
}

detect_os() {
    if [ -z "$os" ] && [ -z "$dist" ]; then
        if [ -e /etc/os-release ]; then
            . /etc/os-release
            os=$ID
            if [ "$os" = "poky" ]; then
                dist="$VERSION_ID"
            elif [ "$os" = "sles" ]; then
                dist="$VERSION_ID"
                os=opensuse
            elif [ "$os" = "opensuse" ]; then
                dist="$VERSION_ID"
            elif [ "$os" = "opensuse-leap" ]; then
                os=opensuse
                dist="$VERSION_ID"
            elif [ "$os" = "amzn" ]; then
                dist="$VERSION_ID"
            else
                dist=$(echo "$VERSION_ID" | awk -F '.' '{ print $1 }')
            fi

        elif command -v lsb_release >/dev/null; then
            # get major version (e.g. '5' or '6')
            dist=$(lsb_release -r | cut -f2 | awk -F '.' '{ print $1 }')

            # get os (e.g. 'centos', 'redhatenterpriseserver', etc)
            os=$(lsb_release -i | cut -f2 | awk '{ print tolower($1) }')

        elif [ -e /etc/oracle-release ]; then
            dist=$(cut -f5 --delimiter=' ' /etc/oracle-release | awk -F '.' '{ print $1 }')
            os='ol'

        elif [ -e /etc/fedora-release ]; then
            dist=$(cut -f3 --delimiter=' ' /etc/fedora-release)
            os='fedora'

        elif [ -e /etc/redhat-release ]; then
            os_hint=$(awk '{ print tolower($1) }' /etc/redhat-release)
            if [ "$os_hint" = "centos" ]; then
                dist=$(awk '{ print $3 }' /etc/redhat-release | awk -F '.' '{ print $1 }')
                os='centos'
            elif [ "$os_hint" = "scientific" ]; then
                dist=$(awk '{ print $4 }' /etc/redhat-release | awk -F '.' '{ print $1 }')
                os='scientific'
            else
                dist=$(awk '{ print tolower($7) }' /etc/redhat-release | cut -f1 --delimiter='.')
                os='redhatenterpriseserver'
            fi

        elif grep -q Amazon /etc/issue; then
            dist='6'
            os='aws'
        else
            unknown_os
        fi
    fi

    # remove whitespace from OS and dist name and transform to lowercase
    os=$(echo "$os" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
    dist=$(echo "$dist" | tr -d ' ' | tr '[:upper:]' '[:lower:]')

    if [ -z "$dist" ]; then
        echo "Detected operating system as $os."
    else
        echo "Detected operating system as $os/$dist."
    fi

    # if [ "$os" = "ol" ] || [ "$os" = "el" ] && [ "$dist" -gt 7 ]; then
    #     _skip_pygpgme=1
    # else
    #     _skip_pygpgme=0
    # fi
    if [ "$os" = "ol" ] && [ "$dist" -ge 8 ]; then
        _skip_pygpgme=1
    elif [ "$os" = "el" ] && [ "$dist" -ge 8 ]; then
        _skip_pygpgme=1
    else
        _skip_pygpgme=0
    fi

}

gpg_check_deb() {
    echo "Checking for gpg..."
    if command -v gpg >/dev/null; then
        echo "Detected gpg..."
    else
        echo "Installing gnupg for GPG verification..."
        if ! apt-get install -y gnupg; then
            echo "Unable to install GPG! Your base system has a problem; please check your default OS's package repositories because GPG should work."
            echo "Repository installation aborted."
            echo
            echo "Please file an issue at https://github.com/crowdsecurity/crowdsec"
            exit 1
        fi
    fi
}

curl_check_deb() {
    echo "Checking for curl..."
    if command -v curl >/dev/null; then
        echo "Detected curl..."
    else
        echo "Installing curl..."

        if apt-get install -q -y curl; then
            echo "Unable to install curl! Your base system has a problem; please check your default OS's package repositories because curl should work."
            echo "Repository installation aborted."
            echo
            echo "Please file an issue at https://github.com/crowdsecurity/crowdsec"
            exit 1
        fi
    fi
}

curl_check_rpm() {
    echo "Checking for curl..."
    if command -v curl >/dev/null; then
        echo "Detected curl..."
    else
        echo "Installing curl..."
        yum install -d0 -e0 -y curl
    fi
}

curl_check_zypper() {
    echo "Checking for curl..."
    if command -v curl >/dev/null; then
        echo "Detected curl..."
    else
        echo "Installing curl..."
        zypper install curl
    fi
}

finalize_yum_repo() {
    if [ "$_skip_pygpgme" = 0 ]; then
        echo "Installing pygpgme to verify GPG signatures..."
        yum install -y pygpgme --disablerepo="crowdsec_${repo}"
        if ! rpm -qa | grep -qw pygpgme; then
            echo
            echo "WARNING: "
            echo "The pygpgme package could not be installed. This means GPG verification is not possible for any RPM installed on your system. "
            echo "To fix this, add a repository with pygpgme. Usually, the EPEL repository for your system will have this. "
            echo "More information: https://fedoraproject.org/wiki/EPEL#How_can_I_use_these_extra_packages.3F"
            echo

            # set the repo_gpgcheck option to 0
            sed -i'' 's/repo_gpgcheck=1/repo_gpgcheck=0/' /etc/yum.repos.d/crowdsec_${repo}.repo
        fi
    fi

    echo "Installing yum-utils..."
    yum install -y yum-utils --disablerepo="crowdsec_${repo}"
    if ! rpm -qa | grep -qw yum-utils; then
        echo
        echo "WARNING: "
        echo "The yum-utils package could not be installed. This means you may not be able to install source RPMs or use other yum features."
        echo
    fi

    echo "Generating yum cache for crowdsec..."
    yum -q makecache -y --disablerepo='*' --enablerepo="crowdsec_${repo}"
}

install_debian_keyring() {
    if [ "$os" = "debian" ]; then
        echo "Installing debian-archive-keyring which is needed for installing "
        echo "apt-transport-https on many Debian systems."
        apt-get install -y debian-archive-keyring >/dev/null 2>&1
    fi
}

detect_apt_version() {
    apt_version_full=$(apt-get -v | head -1 | awk '{ print $2 }')
    apt_version_major=$(echo "$apt_version_full" | cut -d. -f1)
    apt_version_minor=$(echo "$apt_version_full" | cut -d. -f2)
    apt_version_modified="${apt_version_major}${apt_version_minor}0"

    echo "Detected apt version as $apt_version_full"
}

main() {
    if [ -z "$repo" ]; then
        repo="crowdsec"
    fi

    detect_os
    case $os in
    centos | rhel | fedora | redhatentrepriseserver | amzn | cloudlinux | almalinux | opensuse)
        detect_apt_version
        gpg_check_deb
        curl_check_deb
        apt_source_path="/etc/apt/sources.list.d/crowdsec_${repo}.list"
        pre_reqs="apt-transport-https ca-certificates curl"
        if [ -f "$apt_source_path" ]; then
            echo
            echo "The file $apt_source_path already exists: overwriting it."
            echo
        fi
        # needed dependencies
        apt-get update -qq >/dev/null
        #shellcheck disable=SC2086
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $pre_reqs >/dev/null
        # gpg keys
        gpg_key_url="https://packagecloud.io/crowdsec/${repo}/gpgkey"
        apt_keyrings_dir="/etc/apt/keyrings"
        gpg_keyring_path="$apt_keyrings_dir/crowdsec_${repo}-archive-keyring.gpg"
        gpg_key_path_old="/etc/apt/trusted.gpg.d/crowdsec_${repo}.gpg"
        echo
        echo "Importing packagecloud gpg key... "
        echo

            # move gpg key to old path if apt version is older than 1.1
        if [ "$apt_version_modified" -lt 110 ]; then
            curl -fsSL "$gpg_key_url" | gpg --dearmor >"$gpg_key_path_old"
            # grant 644 permisions to gpg key path old
            chmod 0644 "$gpg_key_path_old"

            # deletes the keyrings directory if it is empty
            echo "Packagecloud gpg key imported to $gpg_key_path_old"
        else
            if [ ! -d "$apt_keyrings_dir" ]; then
                install -d -m 0755 "$apt_keyrings_dir"
            fi
            # import the gpg key
            curl -fsSL "$gpg_key_url" | gpg --dearmor >"$gpg_keyring_path"
            # grant 644 permisions to gpg keyring path
            chmod 0644 "$gpg_keyring_path"

            echo "Packagecloud gpg key imported to $gpg_keyring_path"
        fi
        echo
        echo "Installing ${apt_source_path}..."
        echo
        echo "deb [signed-by=/etc/apt/keyrings/crowdsec_${repo}-archive-keyring.gpg] https://packagecloud.io/crowdsec/${repo}/any/ any main" >"$apt_source_path"
        echo "deb-src [signed-by=/etc/apt/keyrings/crowdsec_${repo}-archive-keyring.gpg] https://packagecloud.io/crowdsec/${repo}/any/ any main" >>"$apt_source_path"
        apt-get update -qq >/dev/null

        ;;
    centos | rhel | fedora | redhatentrepriseserver | amzn | cloudlinux | almalinux | opensuse | ol)
        if [ "$os" = "ol" ] && [ "$dist" = "7" ] || [ "$os" = "amzn" ] && [ "$dist" = "2" ]; then
            rpm_repo_config_url="https://packagecloud.io/install/repositories/crowdsec/${repo}/config_file.repo?os=${os}&dist=${dist}&source=script"
        else
            rpm_repo_config_url="https://packagecloud.io/install/repositories/crowdsec/${repo}/config_file.repo?os=rpm_any&dist=rpm_any&source=script"
        fi
        if [ "$os" = "opensuse" ]; then
            curl_check_zypper
            rpm_repo_path=/etc/zypp/repos.d/crowdsec_${repo}.repo
        else
            curl_check_rpm
            rpm_repo_path=/etc/yum.repos.d/crowdsec_${repo}.repo
        fi

        echo "Downloading repository file: $rpm_repo_config_url"

        curl -sSf "$rpm_repo_config_url" >"$rpm_repo_path"
        curl_exit_code=$?
        if [ "$curl_exit_code" = "22" ]; then
            echo
            echo
            echo "Unable to download repo config from: "
            echo "$rpm_repo_config_url"
            echo
            echo "This usually happens if your operating system is not supported by "
            echo "packagecloud.io, or this script's OS detection failed."
            echo
            echo "You can override the OS detection by setting os= and dist= prior to running this script."
            echo "You can find a list of supported OSes and distributions on our website: https://packagecloud.io/docs#os_distro_version"
            echo
            echo "For example, to force CentOS 6: os=el dist=6 ./script.sh"
            echo
            echo "If you are running a supported OS, please file an issue at https://github.com/crowdsecurity/crowdsec."
            [ -e "$rpm_repo_path" ] && rm "$rpm_repo_path"
            exit 1
        elif [ "$curl_exit_code" = "35" ] || [ "$curl_exit_code" = "60" ]; then
            echo
            echo "curl is unable to connect to packagecloud.io over TLS when running: "
            echo "    curl $rpm_repo_config_url"
            echo
            echo "This is usually due to one of two things:"
            echo
            echo " 1.) Missing CA root certificates (make sure the ca-certificates package is installed)"
            echo " 2.) An old version of libssl. Try upgrading libssl on your system to a more recent version"
            echo
            echo "Contact support@crowdsec.net with information about your system for help."
            [ -e "$rpm_repo_path" ] && rm "$rpm_repo_path"
            exit 1
        elif [ "$curl_exit_code" -gt "0" ]; then
            echo
            echo "Unable to run: "
            echo "    curl $rpm_repo_config_url"
            echo
            echo "Double check your curl installation and try again."
            echo
            echo "Please file an issue at https://github.com/crowdsecurity/crowdsec if you think the behavior is not intended"
            [ -e "$rpm_repo_path" ] && rm "$rpm_repo_path"
            exit 1
        else
            echo "done."
        fi
        if [ $os = "opensuse" ]; then
            zypper --gpg-auto-import-keys refresh crowdsec_${repo}
            zypper --gpg-auto-import-keys refresh crowdsec_${repo}-source
        else
            echo ${os}
            finalize_yum_repo
        fi
        ;;
    *)
        echo "Error This system is not supported (yet) by this script."
        echo "Please have a look at documentation https://docs.crowdsec.net/ or"
        echo "file an issue at https://github.com/crowdsecurity/crowdsec if you think"
        echo "the behavior is not intended"

        exit 1
        ;;
    esac

    echo
}

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root"
    echo
    echo "file an issue at https://github.com/crowdsecurity/crowdsec if you think"
    echo "the behavior is not intended"
    exit 1
fi

main
