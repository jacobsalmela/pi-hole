#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2015, 2016 by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# Generates pihole_debug.log to be used for troubleshooting.
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

set -o pipefail

######## GLOBAL VARS ########
VARSFILE="/etc/pihole/setupVars.conf"
DEBUG_LOG="/var/log/pihole_debug.log"
DNSMASQFILE="/etc/dnsmasq.conf"
DNSMASQCONFFILE="/etc/dnsmasq.d/01-pihole.conf"
LIGHTTPDFILE="/etc/lighttpd/lighttpd.conf"
LIGHTTPDERRFILE="/var/log/lighttpd/error.log"
GRAVITYFILE="/etc/pihole/gravity.list"
WHITELISTFILE="/etc/pihole/whitelist.txt"
BLACKLISTFILE="/etc/pihole/blacklist.txt"
ADLISTFILE="/etc/pihole/adlists.list"
PIHOLELOG="/var/log/pihole.log"
WHITELISTMATCHES="/tmp/whitelistmatches.list"


# Header info and introduction
cat << EOM
::: Beginning Pi-hole debug at $(date)!
:::
::: This process collects information from your Pi-hole, and optionally uploads
::: it to a unique and random directory on tricorder.pi-hole.net.
:::
::: NOTE: All log files auto-delete after 24 hours and ONLY the Pi-hole developers
::: can access your data via the given token. We have taken these extra steps to
::: secure your data and will work to further reduce any personal information gathered.
:::
::: Please read and note any issues, and follow any directions advised during this process.
EOM

# Ensure the file exists, create if not, clear if exists.
truncate --size=0 "${DEBUG_LOG}"
chmod 644 ${DEBUG_LOG}
chown "$USER":pihole ${DEBUG_LOG}

# shellcheck source=/dev/null
source ${VARSFILE}

### Private functions exist here ###
log_write() {
    echo "${1}" >> "${DEBUG_LOG}"
}

log_echo() {
  case ${1} in
    -n)
      echo -n ":::       ${2}"
      log_write "${2}"
      ;;
    -r)
      echo ":::       ${2}"
      log_write "${2}"
      ;;
    -l)
      echo "${2}"
      log_write "${2}"
      ;;
     *)
      echo ":::  ${1}"
      log_write "${1}"
  esac
}

header_write() {
  log_echo ""
  log_echo "${1}"
  log_write ""
}

file_parse() {
    while read -r line; do
      if [ ! -z "${line}" ]; then
        [[ "${line}" =~ ^#.*$  || ! "${line}" ]] && continue
        log_write "${line}"
      fi
    done < "${1}"
    log_write ""
}

block_parse() {
  log_write "${1}"
}

version_check() {
  header_write "Detecting Installed Package Versions:"

  local error_found
  local pi_hole_ver
  local admin_ver
  local light_ver
  local php_ver

  pi_hole_ver="$(cd /etc/.pihole/ && git describe --tags --abbrev=0)"
  log_echo "Pi-hole Core Version: ${pi_hole_ver:-"git repository not detected"}"
  [[ "${pi_hole_ver}" ]] || error_found=1

  admin_ver="$(cd /var/www/html/admin && git describe --tags --abbrev=0)"
  log_echo "Pi-hole WebUI Version: ${admin_ver:-"git repository not detected"}"
  [[ "${admin_ver}" ]] || error_found=1

  light_ver="$(lighttpd -v |& head -n1 | cut -d " " -f1)"
  log_echo "${light_ver:-"lighttpd not located"}"
  [[ "${light_ver}" ]] || error_found=1

  php_ver="$(php -v |& head -n1)"
  log_echo "${php_ver:-"PHP not located"}"
  [[ "${php_ver}" ]] || error_found=1

  return "${error_found:-0}"
}

files_check() {
  header_write "Detecting existence of ${1}:"
  local search_file="${1}"
  if [[ -s ${search_file} ]]; then
     log_echo "File exists"
     file_parse "${search_file}"
     return 0
  else
    log_echo "${1} not found!"
    return 1
  fi
  echo ":::"
}

source_file() {
  local file_found

  file_found=$(files_check "${1}")
  if [[ "${file_found}" ]]; then
    # shellcheck source=/dev/null
   (source "${1}" &> /dev/null && echo "${file_found} and was successfully sourced") \
   || log_echo -l "${file_found} and could not be sourced"
  fi
}

distro_check() {
  header_write "Detecting installed OS distribution:"
  local error_found
  local distro

  error_found=0
  distro="$(cat /etc/*release)"
  if [[ "${distro}" ]]; then
    block_parse "${distro}"
  else
    log_echo "Distribution details not found."
    error_found=1
  fi
  return "${error_found}"
}

processor_check() {
  header_write "Checking processor variety"
  log_write "$(uname -m)" && return 0 || return 1
}

ipv6_check() {
  # Check if system is IPv6 enabled, for use in other functions
  if [[ "${IPv6_address}" ]]; then
    ls /proc/net/if_inet6 &>/dev/null
    return 0
  else
    return 1
  fi
}


ip_check() {
  header_write "IP Address Information"

  local IPv6_interface
  local IPv4_interface
  local IPv6_address_list
  local IPv6_default_gateway
  local IPv6_def_gateway_check
  local IPv6_inet_check
  local IPv4_address_list
  local IPv4_defaut_gateway
  local IPv4_def_gateway_check
  local IPv4_inet_check

  # If declared in setupVars.conf use it, otherwise defer to default
  # http://stackoverflow.com/questions/2013547/assigning-default-values-to-shell-variables-with-a-single-command-in-bash

  if [[ $(ipv6_check) -eq 0 ]]; then
    IPv6_address_list="$(ip a | awk -F " " '{ for(i=1;i<=NF;i++) if ($i == "inet6") print $(i+1) }')"
    IPv6_interface=${piholeInterface:-$(ip -6 r | grep default | cut -d ' ' -f 5)}
    IPv6_default_gateway=$(ip -6 r | grep default | cut -d ' ' -f 3)

    if [[ "${IPv6_address_list}" ]]; then
      log_echo "IPv6 addresses found"
      block_parse "${IPv6_address_list}"
      if [[ -n ${IPv6_default_gateway} ]]; then
        echo -n ":::        Pinging default IPv6 gateway: "
        IPv6_def_gateway_check="$(ping6 -q -W 3 -c 3 -n "${IPv6_default_gateway}" -I "${IPv6_interface}"| tail -n3)"
        if [[ -n ${IPv6_def_gateway_check} ]]; then
          echo "Gateway Responded."
          block_parse "${IPv6_def_gateway_check}"
          echo -n ":::        Pinging Internet via IPv6: "
          IPv6_inet_check=$(ping6 -q -W 3 -c 3 -n 2001:4860:4860::8888 -I "${IPv6_interface}"| tail -n3)
          if [[ ${IPv6_inet_check} ]]; then
            echo "Query responded."
            block_parse "${IPv6_inet_check}"
          else
            echo "Query did not respond."
          fi
        else
          echo "Gateway did not respond."
        fi
      else
        log_echo "No IPv6 Gateway Detected"
      fi
    else
      log_echo "IPV6 addresses not found"
    fi
  fi

  IPv4_interface=${piholeInterface:-$(ip r | grep default | cut -d ' ' -f 5)}
  IPv4_address_list="$(ip a | awk -F " " '{ for(i=1;i<=NF;i++) if ($i == "inet") print $(i+1) }')"
  if [[ "${IPv4_address_list}" ]]; then
    log_echo "IPv4 addresses found"
    block_parse "${IPv4_address_list}"
  else
    log_echo "IPv4 addresses not found."
  fi
  IPv4_defaut_gateway=$(ip r | grep default | cut -d ' ' -f 3)
  if [[ "${IPv4_defaut_gateway}" ]]; then
    echo -n ":::        Pinging default IPv4 gateway: "
    IPv4_def_gateway_check="$(ping -q -w 3 -c 3 -n "${IPv4_defaut_gateway}"  -I "${IPv4_interface}" | tail -n3)"
    if [[ "${IPv4_def_gateway_check}" ]]; then
      echo "Gateway responded."
      block_parse "${IPv4_def_gateway_check}"
    else
      echo "Gateway did not respond."
    fi
    echo -n ":::        Pinging Internet via IPv4: "
    IPv4_inet_check="$(ping -q -w 5 -c 3 -n 8.8.8.8 -I "${IPv4_interface}" | tail -n3)" \
    && echo "Query responded." \
    || echo "Query did not respond."
    block_parse "${IPv4_inet_check}"
  fi
}

lsof_parse() {
  local user
  local process

  user=$(echo "${1}" | cut -f 3 -d ' ' | cut -c 2-)
  process=$(echo "${1}" | cut -f 2 -d ' ' | cut -c 2-)
  if [[ ${2} -eq ${process} ]]; then
    echo ":::       Correctly configured."
  else
    log_echo ":::       Failure: Incorrectly configured daemon."
  fi
  log_write "Found user ${user} with process ${process}"
}

port_check() {
  local lsof_value

  lsof_value=$(lsof -i "${1}":"${2}" -FcL | tr '\n' ' ')
  if [[ "${lsof_value}" ]]; then
    lsof_parse "${lsof_value}" "${3}"
  else
    log_echo "Failure: IPv${1} Port not in use"
  fi
}

daemon_check() {
  # Check for daemon ${1} on port ${2}
  header_write "Daemon Process Information"

  echo ":::     Checking ${2} port for ${1} listener."

  if [[ $(ipv6_check) -eq 0 ]]; then
    port_check 6 "${2}" "${1}"
  fi
  port_check 4 "${2}" "${1}"
}

testResolver() {
  header_write "Resolver Functions Check"

  local test_url
  local cut_url
  local cut_url_2
  local local_dig
  local remote_dig

  # Find a blocked url that has not been whitelisted.
  test_url="doubleclick.com"
  if [ -s "${WHITELISTMATCHES}" ]; then
    while read -r line; do
      cut_url=${line#*" "}
      if [ "${cut_url}" != "Pi-Hole.IsWorking.OK" ]; then
        while read -r line2; do
          cut_url_2=${line2#*" "}
          if [ "${cut_url}" != "${cut_url_2}" ]; then
            test_url="${cut_url}"
            break 2
          fi
        done < "${WHITELISTMATCHES}"
      fi
    done < "${GRAVITYFILE}"
  fi

  log_write "Resolution of ${test_url} from Pi-hole:"
  local_dig=$(dig "${test_url}" @127.0.0.1)
  if [[ "${local_dig}" ]]; then
    log_write "${local_dig}"
  else
    log_write "Failed to resolve ${test_url} on Pi-hole"
  fi
  log_write ""


  log_write "Resolution of ${test_url} from 8.8.8.8:"
  remote_dig=$(dig "${test_url}" @8.8.8.8)
  if [[ "${remote_dig}" ]]; then
    log_write "${remote_dig}"
  else
    log_write "Failed to resolve ${test_url} on 8.8.8.8"
  fi
  log_write ""

  log_write "Pi-hole dnsmasq specific records lookups"
  log_write "Cache Size:"
  dig +short chaos txt cachesize.bind >> ${DEBUG_LOG}
  log_write "Upstream Servers:"
  dig +short chaos txt servers.bind >> ${DEBUG_LOG}
  log_write ""
}

checkProcesses() {
  header_write "Processes Check"

  local processes
  echo ":::     Logging status of lighttpd and dnsmasq..."
  processes=( lighttpd dnsmasq )
  for i in "${processes[@]}"; do
    log_write ""
    log_write "${i}"
    log_write " processes status:"
    systemctl -l status "${i}" >> "${DEBUG_LOG}"
  done
  log_write ""
}

debugLighttpd() {
  echo ":::     Checking for necessary lighttpd files."
  files_check "${LIGHTTPDFILE}"
  files_check "${LIGHTTPDERRFILE}"
  echo ":::"
}

dumpPiHoleLog() {
  trap '{ echo -e "\n::: Finishing debug write from interrupt..." ; break;}' SIGINT
  echo "::: "
  echo "::: --= User Action Required =--"
  echo -e "::: Try loading a site that you are having trouble with now from a client web browser.. \n:::\t(Press CTRL+C to finish logging.)"
  header_write "pihole.log"
  if [ -e "${PIHOLELOG}" ]; then
    while true; do
      tail -f "${PIHOLELOG}" >> ${DEBUG_LOG}
      log_write ""
    done
  else
    log_write "No pihole.log file found!"
    printf ":::\tNo pihole.log file found!\n"
  fi
}

finalWork() {
  local tricorder
  echo "::: Finshed debugging!"

  if [[ $(nc -w5 tricorder.pi-hole.net 9999) -eq 0 ]]; then
    echo "::: The debug log can be uploaded to tricorder.pi-hole.net for sharing with developers only."
    read -r -p "::: Would you like to upload the log? [y/N] " response
    case ${response} in
      [yY][eE][sS]|[yY])
        tricorder=$(nc -w 10 tricorder.pi-hole.net 9999 < /var/log/pihole_debug.log)
        ;;
      *)
        echo "::: Log will NOT be uploaded to tricorder."
        ;;
    esac

    if [[ "${tricorder}" ]]; then
      echo ":::"
      log_echo "::: Your debug token is : ${tricorder}"
      echo ":::"
      echo "::: Please contact the Pi-hole team with your token for assistance."
      echo "::: Thank you."
    else
      echo "::: No debug logs will be transmitted..."
    fi
  else
    echo "::: There was an error uploading your debug log."
    echo "::: Please try again or contact the Pi-hole team for assistance."
  fi
echo "::: A local copy of the Debug log can be found at : /var/log/pihole_debug.log"
}

count_gravity() {
header_write "Analyzing gravity.list"

  gravity_length=$(wc -l "${GRAVITYFILE}")
  if [[ "${gravity_length}" ]]; then
    log_write "${GRAVITYFILE} is ${gravity_length} lines long."
  else
    log_echo "Warning: No gravity.list file found!"
  fi
}
### END FUNCTIONS ###

# Gather version of required packages / repositories
version_check || echo "REQUIRED FILES MISSING"
# Check for newer setupVars storage file
source_file "/etc/pihole/setupVars.conf"
# Gather information about the running distribution
distro_check || echo "Distro Check soft fail"
# Gather processor type
processor_check || echo "Processor Check soft fail"

ip_check

daemon_check lighttpd http
daemon_check dnsmasq domain
checkProcesses
testResolver
debugLighttpd

files_check "${DNSMASQFILE}"
files_check "${DNSMASQCONFFILE}"
files_check "${WHITELISTFILE}"
files_check "${BLACKLISTFILE}"
files_check "${ADLISTFILE}"

count_gravity
dumpPiHoleLog

trap finalWork EXIT

