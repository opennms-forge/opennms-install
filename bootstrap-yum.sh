#!/usr/bin/env bash
#
# Copyright 2026 Ronny Trommer <ronny@no42.org>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Script to bootstrap a basic OpenNMS setup

set -eEuo pipefail
# shellcheck disable=SC2154
trap 's=${?}; echo >&2 "${0}: Error on line "${LINENO}": ${BASH_COMMAND}"; exit ${s}' ERR

# Default build identifier set to stable
ERROR_LOG="bootstrap.log"
POSTGRES_USER="postgres"
POSTGRES_PASS="${POSTGRES_PASS:-}"
DB_NAME="${DB_NAME:-opennms}"
DB_USER="${DB_USER:-opennms}"
DB_PASS="${DB_PASS:-opennms}"
# Set ONMS_UNATTENDED=yes to skip the confirmation and credential prompts,
# e.g. for CI. Requires POSTGRES_PASS to be set in the environment.
UNATTENDED="${ONMS_UNATTENDED:-no}"
OPENNMS_HOME="/opt/opennms"
ANSWER="No"
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
ENDCOLOR="\e[0m"
SUPPORTED_DISTROS="RHEL 9/10, CentOS 9/10, Rocky 9/10, Alma 9/10"
REQUIRED_SYSTEMS="^(Red Hat Enterprise Linux|Rocky Linux|CentOS Stream|AlmaLinux) release 9([.][0-9]+)?|10([.][0-9]+)? \(.+\)$"
REQUIRED_JDK="21"
RELEASE_FILE="/etc/redhat-release"
OS_MAJOR_VERSION=$(grep -oE '[0-9]+' /etc/redhat-release | head -1)
PSQL_MAX_VERSION=15
IP_ADDRESS=$(hostname -I | awk '{print $1}') # export the address so it can also be used in the timeout command

# Error codes
E_ILLEGAL_ARGS=126
E_BASH=127
E_UNSUPPORTED=128

####
# Help function used in error messages and -h option
usage() {
  echo ""
  echo "Bootstrap OpenNMS Horizon on RPM-based systems."
  echo "  Supported systems: ${SUPPORTED_DISTROS}"
  echo ""
  echo "-h: Show this help"
}

checkRequirements() {
  echo "#############"
  echo "Welcome to the OpenNMS Horizon installer 👋"
  echo "##########"
  echo ""

  # Test if system is supported
  if ! grep -E "${REQUIRED_SYSTEMS}" "${RELEASE_FILE}" 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"; then
    echo ""
    echo "😔 This is system is not a supported."
    echo "Supported systems are: ${SUPPORTED_DISTROS}"
    echo ""
    exit "${E_UNSUPPORTED}"
  fi

  # The sudo command is required to switch to postgres user for DB setup
  if ! command -v sudo 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"; then
    echo ""
    echo "This script requires sudo which could not be found."
    echo "Please install the sudo package."
    echo ""
    exit "${E_BASH}"
  fi

  # The timeout command is required to testing the availability of the web application
  if ! command -v timeout 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"; then
    echo ""
    echo "This script requires timeout which could not be found."
    echo "Please install the coreutils package."
    echo ""
    exit "${E_BASH}"
  fi
}

showDisclaimer() {
  echo ""
  echo "This script installs OpenNMS on a clean system with the following."
  echo "components:"
  echo ""
  echo " - Installing curl"
  echo " - Eclipse Adoptium Temurin JDK ${REQUIRED_JDK}"
  echo " - PostgreSQL Server"
  echo " - Initializing database access with credentials"
  echo " - OpenNMS Repositories"
  echo " - OpenNMS with core services and web application"
  echo " - Initializing and bootstrapping the OpenNMS database schema"
  echo " - Start OpenNMS"
  echo ""
  echo "If you have OpenNMS already installed, don't use this script!"
  echo ""
  echo "If you get any errors during the install procedure please visit the"
  echo "bootstrap.log where you can find detailed error messages for"
  echo "diagnose and bug reporting."
  echo ""
  echo "Bugs or enhancements can be reported here:"
  echo ""
  echo " - https://github.com/opennms-forge/opennms-install/issues -"
  echo ""

  if [[ "${UNATTENDED}" == "yes" ]]; then
    echo "🤖 Unattended mode, skipping confirmation"
    echo ""
    echo "🚀 Starting setup procedure"
    echo ""
    return
  fi

  read -r -p "If you want to proceed, type YES: " ANSWER

  # Set bash to case insensitive
  shopt -s nocasematch

  if [[ "${ANSWER}" == "yes" ]]; then
    echo ""
    echo "🚀 Starting setup procedure"
    echo ""
  else
    echo ""
    echo "Your system is unchanged."
    echo "Thank you for computing with us"
    echo ""
    exit "${E_BASH}"
  fi

  # Set case sensitive
  shopt -u nocasematch
}

####
# The -r option is optional and allows to set the release of OpenNMS.
# The -m option allows to overwrite the package repository server.
while getopts h flag; do
  case "${flag}" in
    h)
      usage
      exit "${E_ILLEGAL_ARGS}"
      ;;
    *)
      usage
      exit "${E_ILLEGAL_ARGS}"
      ;;
  esac
done

####
# Helper function which tests if a command was successful or failed
checkError() {
  if [[ "${1}" -eq 0 ]]; then
    echo -e "[ ${GREEN}OK${ENDCOLOR} ]"
  else
    echo -e "[ ${RED}FAILED${ENDCOLOR} ]"
    exit "${E_BASH}"
  fi
}

prepare() {
  echo "👮 Authenticate with sudo                ... "
  sudo echo -n "" 2>>"${ERROR_LOG}"
  checkError "${?}"

  # Ensure curl and gnupg2 is available
  # --allowerasing: EL ships curl-minimal which conflicts with curl
  echo -n "📦 Install curl                          ... "
  sudo dnf -y install --allowerasing curl 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"
  checkError "${?}"
}

####
# Helper to request Postgres credentials to initialize the
# OpenNMS database.
queryDbCredentials() {
  if [[ "${UNATTENDED}" == "yes" ]]; then
    if [[ -z "${POSTGRES_PASS}" ]]; then
      echo "Unattended mode requires the POSTGRES_PASS environment variable to be set."
      exit "${E_ILLEGAL_ARGS}"
    fi
    return
  fi

  echo "👩‍💻 Enter credentials for the database and connection"
  echo "   Set a Postgres root password"
  while true; do
    read -r -s -p "   New postgres password: " POSTGRES_PASS
    echo ""
    read -r -s -p "   Confirm postgres password: " POSTGRES_PASS_CONFIRM
    echo ""
    if [ -n "${POSTGRES_PASS}" ]; then
      [ "${POSTGRES_PASS}" = "${POSTGRES_PASS_CONFIRM}" ] && break
      echo "Password confirmation didn't match, please try again."
    else
      echo "Password for the PostgreSQL user can't be empty. Please set a password."
    fi
    echo ""
  done
  echo ""
  echo "👩‍💻 Create OpenNMS Horizon database with user credentials"
  read -r -p "   Set database name for OpenNMS Horizon (default: opennms): " DB_NAME
  DB_NAME="${DB_NAME:-opennms}"
  read -r -p "   User for the database (default: opennms): " DB_USER
  DB_USER="${DB_USER:-opennms}"
  while true; do
    read -r -s -p "   New password: " DB_PASS
    echo ""
    read -r -s -p "   Confirm password: " DB_PASS_CONFIRM
    echo ""
    if [ -n "${DB_PASS}" ]; then
      [ "${DB_PASS}" = "${DB_PASS_CONFIRM}" ] && break
      echo "Password confirmation didn't match, please try again."
    else
      echo "Password for the OpenNMS database user can't be empty. Please set a password."
    fi
    echo ""
  done
  echo ""
}

setDbCredentials() {
  echo -n "✨ Enable SCRAM-SHA-256 in PostgreSQL    ... "
  sudo -i -u postgres psql -c "ALTER SYSTEM SET password_encryption = 'scram-sha-256';" 1>"${ERROR_LOG}" 2>>"${ERROR_LOG}"
  checkError "${?}"
  echo -n "🔄 Restart PostgreSQL Server             ... "
  sudo systemctl restart postgresql-${PSQL_MAX_VERSION} 1>"${ERROR_LOG}" 2>>"${ERROR_LOG}"
  checkError "${?}"
  echo -n "👩‍🔧 Create database and users             ... "
  {
    # Escape single quotes in password for safe SQL usage
    ESCAPED_DBUSER_PASS="${DB_PASS//\'/\'\'}"
    ESCAPED_POSTGRES_PASS="${POSTGRES_PASS//\'/\'\'}"
    sudo -i -u postgres psql <<EOF
ALTER ROLE postgres WITH PASSWORD '$ESCAPED_POSTGRES_PASS';
EOF
    sudo -i -u postgres psql <<EOF
CREATE USER ${DB_USER} WITH PASSWORD '$ESCAPED_DBUSER_PASS';
EOF
    sudo -i -u postgres psql -c "GRANT CREATE ON SCHEMA public TO PUBLIC;"
    sudo -i -u postgres psql -c "CREATE DATABASE ${DB_NAME} WITH OWNER ${DB_USER} ENCODING UTF8 TEMPLATE template0;"
  } 1>"${ERROR_LOG}" 2>>"${ERROR_LOG}"
  checkError "${?}"
}

####
# Install Eclipse Adoptium Temurin JDK
installJdk() {
  echo "📦 Adding Adoptium Repo                  ... "
  # Use the OS major version: Adoptium only publishes per-major repos, and
  # $releasever expands to e.g. 9.6 on RHEL EUS/RHUI systems, which 404s.
  cat <<EOF | sudo tee /etc/yum.repos.d/adoptium.repo > /dev/null
[Adoptium]
name=Adoptium
baseurl=https://packages.adoptium.net/artifactory/rpm/centos/${OS_MAJOR_VERSION}/\$basearch
enabled=1
gpgcheck=1
gpgkey=https://packages.adoptium.net/artifactory/api/gpg/key/public
EOF
  echo -n "📦 Install Temurin Java Development Kit  ... "
  sudo dnf -y install temurin-"${REQUIRED_JDK}"-jdk 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"
  checkError "${?}"
}

####
# Install the PostgreSQL database
installPostgres() {
  echo "📦 Add PostgreSQL repository             ... "
  sudo dnf install -y "https://download.postgresql.org/pub/repos/yum/reporpms/EL-${OS_MAJOR_VERSION}-$(uname -m)/pgdg-redhat-repo-latest.noarch.rpm"
  checkError "${?}"
  echo -n "📦 Install PostgreSQL ${PSQL_MAX_VERSION} database        ... "
  sudo dnf install -y postgresql${PSQL_MAX_VERSION}-server 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"
  checkError "${?}"
}

####
# Install OpenNMS rpm repository for specific release
installOnmsRepo() {
  echo -n "📦 Install OpenNMS repository            ... "
  sudo dnf -y install "https://yum.opennms.org/repofiles/opennms-repo-stable-rhel${OS_MAJOR_VERSION}.noarch.rpm" 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"
  checkError "${?}"
  echo -n "📦 Disable GPG check on repository       ... "
  sudo sed -i 's/gpgcheck=1/gpgcheck=0/g' /etc/yum.repos.d/opennms-repo-stable-*.repo 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"
  checkError "${?}"
}

####
# Install the OpenNMS application from rpm repository
installOnmsApp() {
  echo -n "📦 Install OpenNMS Horizon packages      ... "
  sudo dnf -y install rrdtool jrrd2 jicmp jicmp6 opennms-core opennms-webapp-jetty opennms-webapp-hawtio 1>>"${ERROR_LOG}" 2>>${ERROR_LOG}
  sudo -u opennms "${OPENNMS_HOME}"/bin/runjava -s 1>>"${ERROR_LOG}" 2>>${ERROR_LOG}
  checkError "${?}"
}

####
# Generate OpenNMS configuration file for accessing the PostgreSQL
# Database with credentials
setCredentials() {
  echo ""
  echo -n "👩‍🔧 Create secure vault for Postgres      ... "
  sudo -u opennms "${OPENNMS_HOME}/bin/scvcli" set postgres-admin "${POSTGRES_USER}" "${POSTGRES_PASS}" 1>/dev/null 2>>"${ERROR_LOG}"
  sudo -u opennms "${OPENNMS_HOME}/bin/scvcli" set postgres "${DB_USER}" "${DB_PASS}" 1>/dev/null 2>>"${ERROR_LOG}"
  checkError "${?}"
  echo -n "🔧 Generate OpenNMS database config      ... "
  if [[ -f "${OPENNMS_HOME}"/etc/opennms-datasources.xml ]]; then
    printf '<?xml version="1.0" encoding="UTF-8"?>
<datasource-configuration xmlns:this="http://xmlns.opennms.org/xsd/config/opennms-datasources"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://xmlns.opennms.org/xsd/config/opennms-datasources
  http://www.opennms.org/xsd/config/opennms-datasources.xsd ">

  <connection-pool factory="org.opennms.core.db.HikariCPConnectionFactory"
      idleTimeout="600"
      loginTimeout="3"
      minPool="25"
      maxPool="50"
      maxSize="50" />

  <jdbc-data-source name="opennms"
                    database-name="%s"
                    class-name="org.postgresql.Driver"
                    url="jdbc:postgresql://localhost:5432/%s"
                    user-name="${scv:postgres:username}"
                    password="${scv:postgres:password}" />

  <jdbc-data-source name="opennms-admin"
                    database-name="template1"
                    class-name="org.postgresql.Driver"
                    url="jdbc:postgresql://localhost:5432/template1"
                    user-name="${scv:postgres-admin:username}"
                    password="${scv:postgres-admin:password}">
    <connection-pool idleTimeout="600"
                     minPool="0"
                     maxPool="10"
                     maxSize="50" />
  </jdbc-data-source>

  <jdbc-data-source name="opennms-monitor"
                    database-name="postgres"
                    class-name="org.postgresql.Driver"
                    url="jdbc:postgresql://localhost:5432/postgres"
                    user-name="${scv:postgres-admin:username}"
                    password="${scv:postgres-admin:password}">
    <connection-pool idleTimeout="600"
                     minPool="0"
                     maxPool="10"
                     maxSize="50" />
  </jdbc-data-source>
</datasource-configuration>' "${DB_NAME}" "${DB_NAME}" \
  | sudo -u opennms tee "${OPENNMS_HOME}"/etc/opennms-datasources.xml 1>>/dev/null 2>>"${ERROR_LOG}"
  checkError "${?}"
  else
    echo "No OpenNMS configuration found in ${OPENNMS_HOME}/etc"
    exit "${E_ILLEGAL_ARGS}"
  fi
}

####
# Helper script to initialize the PostgreSQL database
initializePostgres() {
  echo -n "👩‍🔧 PostgreSQL initialize                 ... "
  sudo postgresql-${PSQL_MAX_VERSION}-setup initdb 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"
  checkError "${?}"
  echo -n "🚀 Start PostgreSQL database             ... "
  sudo systemctl start postgresql-${PSQL_MAX_VERSION}
  checkError "${?}"
  echo -n "🚀 PostgreSQL systemd enable             ... "
  sudo systemctl enable postgresql-${PSQL_MAX_VERSION} 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"
  checkError "${?}"
}

####
# Initialize the OpenNMS database schema
initializeOnmsDb() {
  echo -n "🔧 Initialize OpenNMS                    ... "
  sudo -u opennms "${OPENNMS_HOME}"/bin/install -dis 1>>"${ERROR_LOG}" 2>>${ERROR_LOG}
  checkError "${?}"
}

restartOnms() {
  echo -n "🚀 Starting OpenNMS                      ... "
  sudo systemctl start opennms 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"
  checkError "${?}"
  echo -n "🚀 OpenNMS systemd enable                ... "
  sudo systemctl enable opennms 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"
  checkError "${?}"

  # If firewalld is enabled, then open a port in the firewall, else skip it. 
  echo -n "👩‍🔧 Checking if firewalld is enabled      ... "
  if systemctl status firewalld.service >/dev/null 2>&1; then
    echo -e "[ ${GREEN}ENABLED${ENDCOLOR} ]"  # Defined the colour manually as can't use checkerror() due to exit command.
    echo -n "👩‍🔧 Opening Web UI port 8980/tcp          ... "
    sudo firewall-cmd --permanent --add-port=8980/tcp 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"
    checkError "${?}"
    echo -n "👩‍🔧 Opening SNMP Trap port 10162/udp      ... "
    sudo firewall-cmd --permanent --add-port=10162/udp 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"
    checkError "${?}"
    echo -n "👩‍🔧 Opening Network flow port 9999/udp    ... "
    sudo firewall-cmd --permanent --add-port=9999/udp 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"
    checkError "${?}"
    echo -n "🔄 Reload Firewalld configuration        ... "
    sudo systemctl reload firewalld.service 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"
    checkError "${?}"
  else
    echo -e "[ ${YELLOW}DISABLED - SKIP${ENDCOLOR} ]" # Defined the colour manually as can't use checkerror() due to exit command.
  fi
}

lockdownDbUser() {
  echo -n "👮 PostgreSQL revoke super user role     ... "
  sudo -i -u postgres psql -c "ALTER ROLE \"${DB_USER}\" NOSUPERUSER;" 1>>"${ERROR_LOG}" 2>>${ERROR_LOG}
  checkError "${?}"
  echo -n "👮 PostgreSQL revoke create db role      ... "
  sudo -i -u postgres psql -c "ALTER ROLE \"${DB_USER}\" NOCREATEDB;" 1>>"${ERROR_LOG}" 2>>${ERROR_LOG}
  checkError "${?}"
}

# Disable the repo and lock the versions. 
disableRepo() {
  echo -n "👮 Disabling autoupdates                 ... "
  # Rocky 10 ships dnf5 without the config-manager plugin; fall back to
  # disabling the repo file directly.
  sudo dnf config-manager --disable "opennms-repo-stable-*" 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}" \
    || sudo sed -i 's/^enabled=1/enabled=0/' /etc/yum.repos.d/opennms-repo-stable-*.repo 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"
  checkError "${?}"
}

# Wait 20 seconds for OpenNMS to start. 
waitForStart() {
  echo -n "Wait for the Web UI (timeout 2m)      ... "
  timeout 120s bash -c "until curl -f -I -L http://${IP_ADDRESS}:8980; do sleep 1; done" 1>/dev/null 2>/dev/null
  checkError "${?}"
}

# Execute setup procedure
clear 2>/dev/null || true # No TTY in unattended runs
checkRequirements
showDisclaimer
prepare
queryDbCredentials
installJdk
installPostgres
initializePostgres
setDbCredentials
installOnmsRepo
installOnmsApp
setCredentials
initializeOnmsDb
lockdownDbUser
restartOnms
disableRepo
waitForStart

echo ""
echo "Congratulations"
echo "---------------"
echo ""
echo "OpenNMS is starting up and might take a few seconds. You can access the"
echo "web application with"
echo ""
echo "  http://${IP_ADDRESS}:8980"
echo ""
echo "Login with username admin and password admin"
echo ""
echo "Please change immediately the password for your admin user!"
echo "Select in the main navigation \"Admin\" and go to \"Change Password\""
echo ""
echo "🦄 Thank you for computing with us. ✨"
echo ""
