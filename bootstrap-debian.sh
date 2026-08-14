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
export DEBIAN_FRONTEND=noninteractive
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
ENDCOLOR="\e[0m"

REQUIRED_SYSTEMS="Ubuntu|Debian"
REQUIRED_JDK="21"
PSQL_VERSION=18
# OpenNMS Horizon version of the certified combo. Deb and rpm installs pin
# this exact version; bumping it requires a green CI matrix (re-certification).
ONMS_VERSION=36.0.3
IP_ADDRESS=$(hostname -I | awk '{print $1}') # export the address so it can also be used in the timeout command

# Error codes
E_ILLEGAL_ARGS=126
E_BASH=127
E_UNSUPPORTED=128

####
# Help function used in error messages and -h option
usage() {
  echo ""
  echo "Bootstrap OpenNMS basic setup on Debian based system."
  echo ""
  echo "-h: Show this help"
}

checkRequirements() {
  echo "#############"
  echo "Welcome to the OpenNMS Horizon installer 👋"
  echo "##########"
  echo ""

  # The lsb_release is required
  if ! command -v lsb_release 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"; then
    echo ""
    echo "This script requires lsb_release could not be found."
    echo "Please install the lsb-release package."
    echo ""
    exit "${E_BASH}"
  fi

  # Test if system is supported
  if ! lsb_release -a | grep -E "${REQUIRED_SYSTEMS}" 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}" && [[ ! -e /etc/debian_version ]]; then
    echo ""
    echo "This is system is not a supported Ubuntu or Debian system."
    echo ""
    exit "${E_UNSUPPORTED}"
  fi

  # The sudo command is required to switch to postgres user for DB setup
  if ! command -v sudo 1>>"${ERROR_LOG}" 2>"${ERROR_LOG}"; then
    echo ""
    echo "This script requires sudo and could not be found."
    echo "Please install the sudo package."
    echo ""
    exit "${E_BASH}"
  fi

  # The timeout command is required to testing the availability of the web application
  if ! command -v timeout 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"; then
    echo ""
    echo "This script requires timeout and could not be found."
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
  echo " - Installing installer dependencies curl, gnupg2, apt-transport-https"
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
  echo -n "👮 Authenticate with sudo                ... "
  sudo echo -n "" 2>>"${ERROR_LOG}"
  checkError "${?}"
  echo -n "📦 Update APT cache                      ... "
  sudo apt-get update 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"
  checkError "${?}"

  # Ensure curl, gnupg2 abd apt-transport-https is available
  echo -n "📦 Install dependencies                  ... "
  sudo apt-get -y install gnupg2 curl apt-transport-https lsb-release 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"
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
    if [ ! -z "${POSTGRES_PASS}" ]; then
      [ "${POSTGRES_PASS}" = "${POSTGRES_PASS_CONFIRM}" ] && break
      echo "Password confirmation didn't match, please try again."
    else
      echo "Password for the PostgreSQL user can't be empty. Please set a password."
    fi
    echo ""
  done
  echo ""
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
    if [ ! -z "${DB_PASS}" ]; then
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
  sudo systemctl restart postgresql 1>"${ERROR_LOG}" 2>>"${ERROR_LOG}"
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
  if dpkg -s "temurin-${REQUIRED_JDK}-jdk" 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"; then
    echo "📦 Install Temurin Java Development Kit  ... [ SKIP ] Already installed"
    return
  fi
  DEB_CODENAME="$(lsb_release -cs)"
  echo -n "📦 Check Adoptium supports your system   ... "
  if ! curl -1sLf -o /dev/null "https://packages.adoptium.net/artifactory/deb/dists/${DEB_CODENAME}/Release" 2>>"${ERROR_LOG}"; then
    echo -e "[ ${RED}FAILED${ENDCOLOR} ]"
    echo ""
    echo "The Adoptium apt repository does not publish packages for '${DEB_CODENAME}'."
    echo "See https://packages.adoptium.net/artifactory/deb/dists/ for supported"
    echo "releases, or install a Temurin ${REQUIRED_JDK} JDK manually and re-run this script."
    echo ""
    exit "${E_UNSUPPORTED}"
  fi
  echo -e "[ ${GREEN}OK${ENDCOLOR} ]"
  echo -n "📦 Add Adoptium repository key           ... "
  curl -1sLf "https://packages.adoptium.net/artifactory/api/gpg/key/public" | gpg --dearmor | sudo tee "/usr/share/keyrings/adoptium.gpg" 1>/dev/null 2>>"${ERROR_LOG}"
  checkError "${?}"
  echo -n "📦 Add Adoptium repository               ... "
  echo "deb [signed-by=/usr/share/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb ${DEB_CODENAME} main" | sudo tee /etc/apt/sources.list.d/adoptium.list 1>/dev/null 2>>"${ERROR_LOG}"
  checkError "${?}"
  echo -n "📦 Update apt cache                      ... "
  sudo apt-get update 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"
  checkError "${?}"
  echo -n "📦 Install Temurin Java Development Kit  ... "
  # sudo's env_reset strips the exported DEBIAN_FRONTEND, so pass it on the
  # command line for every apt-get install, or debconf prompts (e.g. the
  # opennms-db/noinstall note) block the bootstrap on real terminals, issue #32.
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "temurin-${REQUIRED_JDK}-jdk" 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"
  checkError "${?}"
}

####
# Install the PostgreSQL database
installPostgres() {
  echo -n "📦 Add PostgreSQL repository key         ... "
  curl -1sLf "https://www.postgresql.org/media/keys/ACCC4CF8.asc" | gpg --dearmor | sudo tee "/usr/share/keyrings/postgresql.gpg" 1>/dev/null 2>>"${ERROR_LOG}"
  checkError "${?}"
  echo -n "📦 Add PostgreSQL repository             ... "
  echo "deb [arch=amd64,arm64,ppc64el signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" | sudo tee /etc/apt/sources.list.d/postgresql.list 1>/dev/null 2>>"${ERROR_LOG}"
  checkError "${?}"
  echo -n "📦 Update apt cache                      ... "
  sudo apt-get update 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"
  checkError "${?}"
  echo -n "📦 Install PostgreSQL database           ... "
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-${PSQL_VERSION} 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"
  checkError "${?}"
  # The postinst normally starts the cluster; make sure it runs on systems
  # where deferred service starts are policy (e.g. containers).
  echo -n "🚀 Start PostgreSQL database             ... "
  sudo systemctl start postgresql 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"
  checkError "${?}"
}

####
# Install OpenNMS Debian repository for specific release
installOnmsRepo() {
  echo -n "📦 Add OpenNMS repository key            ... "
  curl -1sLf "https://debian.opennms.org/OPENNMS-GPG-KEY" | gpg --dearmor | sudo tee "/usr/share/keyrings/opennms.gpg" 1>/dev/null 2>>"${ERROR_LOG}"
  checkError "${?}"
  echo -n "📦 Add OpenNMS repository                ... "
  echo "deb [signed-by=/usr/share/keyrings/opennms.gpg] https://debian.opennms.org stable main" | sudo tee /etc/apt/sources.list.d/opennms.list 1>/dev/null 2>>"${ERROR_LOG}"
  checkError "${?}"
  echo -n "📦 Update apt cache                      ... "
  sudo apt-get update 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"
  checkError "${?}"
}

####
# Install the OpenNMS application from Debian repository
installOnmsApp() {
  echo -n "📦 Install OpenNMS Horizon packages      ... "
  # --no-install-recommends: opennms recommends openjdk-21, which apt would
  # install next to the Temurin JDK because temurin-21-jdk does not provide
  # any name in the recommends list, see issue #48.
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends rrdtool jrrd2 jicmp jicmp6 opennms="${ONMS_VERSION}-*" opennms-webapp-hawtio="${ONMS_VERSION}-*" 2>>"${ERROR_LOG}"
  sudo -u opennms "${OPENNMS_HOME}"/bin/runjava -s 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"
  checkError "${?}"
}

####
# Generate OpenNMS configuration file for accessing the PostgreSQL
# Database with credentials
setCredentials() {
  echo ""
  echo -n "👩‍🔧 Create secure vault for Postgres      ... "
  # Run scvcli with bash: the script uses the bashism $(<java.conf) but has
  # a /bin/sh shebang, which breaks on Debian where /bin/sh is dash.
  sudo -u opennms bash "${OPENNMS_HOME}/bin/scvcli" set postgres "${DB_USER}" "${DB_PASS}" 1>/dev/null 2>>"${ERROR_LOG}"
  sudo -u opennms bash "${OPENNMS_HOME}/bin/scvcli" set postgres-admin "${POSTGRES_USER}" "${POSTGRES_PASS}" 1>/dev/null 2>>"${ERROR_LOG}"
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
# Initialize the OpenNMS database schema
initializeOnmsDb() {
  echo -n "🔧 Initialize OpenNMS                    ... "
  sudo "${OPENNMS_HOME}"/bin/install -dis 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"
  checkError "${?}"
}

restartOnms() {
  echo -n "🚀 Starting OpenNMS                      ... "
  sudo systemctl start opennms 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"
  checkError "${?}"
  echo -n "🚀 OpenNMS systemd enable                ... "
  sudo systemctl enable opennms 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"
  checkError "${?}"
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
  sudo apt-mark hold libopennms-java \
    libopennmsdeps-java \
    opennms \
    opennms-common \
    opennms-db \
    opennms-server \
    opennms-source \
    opennms-webapp-hawtio \
    opennms-webapp-jetty 1>/dev/null 2>>${ERROR_LOG}
  checkError "${?}"
}

# Wait 20 seconds for OpenNMS to start.
waitForStart() {
  echo -n "🛌 Wait for the Web UI (timeout 2m)      ... "
  timeout 180s bash -c "until curl -f -I -L http://${IP_ADDRESS}:8980; do sleep 1; done" 1>/dev/null 2>/dev/null
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
