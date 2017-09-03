#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Completely uninstalls Pi-hole
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

source "/opt/pihole/COL_TABLE"

while true; do
	read -rp "  ${QST} Are you sure you would like to remove ${COL_WHITE}Pi-hole${COL_NC}? [y/N] " yn
	case ${yn} in
		[Yy]* ) break;;
		[Nn]* ) echo -e "\n  ${COL_LIGHT_GREEN}Uninstall has been cancelled${COL_NC}"; exit 0;;
    * ) echo -e "\n  ${COL_LIGHT_GREEN}Uninstall has been cancelled${COL_NC}"; exit 0;;
	esac
done

# Must be root to uninstall
str="Root user check"
if [[ ${EUID} -eq 0 ]]; then
	echo -e "  ${TICK} ${str}"
else
	# Check if sudo is actually installed
	# If it isn't, exit because the uninstall can not complete
	if [ -x "$(command -v sudo)" ]; then
		export SUDO="sudo"
	else
    echo -e "  ${CROSS} ${str}
       Script called with non-root privileges
       The Pi-hole requires elevated privleges to uninstall"
		exit 1
	fi
fi

# Compatability
if [ -x "$(command -v rpm)" ]; then
	# Fedora Family
	if [ -x "$(command -v dnf)" ]; then
		PKG_MANAGER="dnf"
	else
		PKG_MANAGER="yum"
	fi
	PKG_REMOVE="${PKG_MANAGER} remove -y"
	PIHOLE_DEPS=( bind-utils bc dnsmasq lighttpd lighttpd-fastcgi php-common git curl unzip wget findutils )
	package_check() {
		rpm -qa | grep ^$1- > /dev/null
	}
	package_cleanup() {
		${SUDO} ${PKG_MANAGER} -y autoremove
	}
elif [ -x "$(command -v apt-get)" ]; then
	# Debian Family
	PKG_MANAGER="apt-get"
	PKG_REMOVE="${PKG_MANAGER} -y remove --purge"
	PIHOLE_DEPS=( dnsutils bc dnsmasq lighttpd php5-common git curl unzip wget )
	package_check() {
		dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -c "ok installed"
	}
	package_cleanup() {
		${SUDO} ${PKG_MANAGER} -y autoremove
		${SUDO} ${PKG_MANAGER} -y autoclean
	}
else
  echo -e "  ${CROSS} OS distribution not supported"
	exit 1
fi

removeAndPurge() {
	# Purge dependencies
  echo ""
	for i in "${PIHOLE_DEPS[@]}"; do
		package_check ${i} > /dev/null
		if [[ "$?" -eq 0 ]]; then
			while true; do
				read -rp "  ${QST} Do you wish to remove ${COL_WHITE}${i}${COL_NC} from your system? [Y/N] " yn
				case ${yn} in
					[Yy]* )
            echo -ne "  ${INFO} Removing ${i}...";
            ${SUDO} ${PKG_REMOVE} "${i}" &> /dev/null;
            echo -e "${OVER}  ${INFO} Removed ${i}";
            break;;
					[Nn]* ) echo -e "  ${INFO} Skipped ${i}"; break;;
				esac
			done
		else
			echo -e "  ${INFO} Package ${i} not installed"
		fi
	done

	# Remove dnsmasq config files
	${SUDO} rm /etc/dnsmasq.conf /etc/dnsmasq.conf.orig /etc/dnsmasq.d/01-pihole.conf &> /dev/null
  echo -e "  ${TICK} Removing dnsmasq config files"
  
	# Take care of any additional package cleaning
	echo -ne "  ${INFO} Removing & cleaning remaining dependencies..."
	package_cleanup &> /dev/null
  echo -e "${OVER}  ${TICK} Removed & cleaned up remaining dependencies"
  
	# Call removeNoPurge to remove Pi-hole specific files
	removeNoPurge
}

removeNoPurge() {
	# Only web directories/files that are created by Pi-hole should be removed
	echo -ne "  ${INFO} Removing Web Interface..."
	${SUDO} rm -rf /var/www/html/admin &> /dev/null
	${SUDO} rm -rf /var/www/html/pihole &> /dev/null
	${SUDO} rm /var/www/html/index.lighttpd.orig &> /dev/null

	# If the web directory is empty after removing these files, then the parent html folder can be removed.
	if [ -d "/var/www/html" ]; then
		if [[ ! "$(ls -A /var/www/html)" ]]; then
    			${SUDO} rm -rf /var/www/html &> /dev/null
		fi
	fi
  echo -e "${OVER}  ${TICK} Removed Web Interface"

	# Attempt to preserve backwards compatibility with older versions
	# to guarantee no additional changes were made to /etc/crontab after
	# the installation of pihole, /etc/crontab.pihole should be permanently
	# preserved.
	if [[ -f /etc/crontab.orig ]]; then
		${SUDO} mv /etc/crontab /etc/crontab.pihole
		${SUDO} mv /etc/crontab.orig /etc/crontab
		${SUDO} service cron restart
    echo -e "  ${TICK} Restored the default system cron"
	fi

	# Attempt to preserve backwards compatibility with older versions
	if [[ -f /etc/cron.d/pihole ]];then
		${SUDO} rm /etc/cron.d/pihole &> /dev/null
    echo -e "  ${TICK} Removed /etc/cron.d/pihole"
	fi

	package_check lighttpd > /dev/null
	if [[ $? -eq 1 ]]; then
		${SUDO} rm -rf /etc/lighttpd/ &> /dev/null
    	echo -e "  ${TICK} Removed lighttpd"
	else
		if [ -f /etc/lighttpd/lighttpd.conf.orig ]; then
			${SUDO} mv /etc/lighttpd/lighttpd.conf.orig /etc/lighttpd/lighttpd.conf
		fi
	fi
  
	${SUDO} rm /etc/dnsmasq.d/adList.conf &> /dev/null
	${SUDO} rm /etc/dnsmasq.d/01-pihole.conf &> /dev/null
	${SUDO} rm -rf /var/log/*pihole* &> /dev/null
	${SUDO} rm -rf /etc/pihole/ &> /dev/null
	${SUDO} rm -rf /etc/.pihole/ &> /dev/null
	${SUDO} rm -rf /opt/pihole/ &> /dev/null
	${SUDO} rm -rf /var/lib/pihole/ &> /dev/null
	${SUDO} rm /usr/local/bin/pihole &> /dev/null
	${SUDO} rm /etc/bash_completion.d/pihole &> /dev/null
	${SUDO} rm /etc/sudoers.d/pihole &> /dev/null
  echo -e "  ${TICK} Removed config files"
  
  # Remove FTL
  if command -v pihole-FTL &> /dev/null; then
    echo -ne "  ${INFO} Removing pihole-FTL..."
    
    if [[ -x "$(command -v systemctl)" ]]; then
      systemctl stop pihole-FTL
    else
      service pihole-FTL stop
    fi
    
    ${SUDO} rm /etc/init.d/pihole-FTL
    ${SUDO} rm /usr/bin/pihole-FTL
    
    echo -e "${OVER}  ${TICK} Removed pihole-FTL"
  fi
  
	# If the pihole user exists, then remove
	if id "pihole" &> /dev/null; then
		${SUDO} userdel -r pihole 2> /dev/null
    if [[ "$?" -eq 0 ]]; then
      echo -e "  ${TICK} Removed 'pihole' user"
    else
      echo -e "  ${CROSS} Unable to remove 'pihole' user"
    fi
	fi

  echo -e "\n   We're sorry to see you go, but thanks for checking out Pi-hole!
   If you need help, reach out to us on Github, Discourse, Reddit or Twitter
   Reinstall at any time: ${COL_WHITE}curl -sSL https://install.pi-hole.net | bash${COL_NC}

  ${COL_LIGHT_RED}Please reset the DNS on your router/clients to restore internet connectivity
  ${COL_LIGHT_GREEN}Uninstallation Complete! ${COL_NC}"
}

######### SCRIPT ###########
if command -v vcgencmd &> /dev/null; then
  echo -e "  ${INFO} All dependencies are safe to remove on Raspbian"
else
  echo -e "  ${INFO} Be sure to confirm if any dependencies should not be removed"
fi
while true; do
	read -rp "  ${QST} Do you wish to go through each dependency for removal? [Y/n] " yn
	case ${yn} in
		[Yy]* ) removeAndPurge; break;;
		[Nn]* ) removeNoPurge; break;;
    * ) removeAndPurge; break;;
	esac
done
