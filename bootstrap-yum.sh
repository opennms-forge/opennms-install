#!/usr/bin/env bash
#
# Script to bootstrap a basic OpenNMS setup

# Default build identifier set to stable
RELEASE="stable"
ERROR_LOG="bootstrap.log"
DB_USER="opennms"
DB_PASS="opennms"
OPENNMS_HOME="/opt/opennms"
REQUIRED_USER="root"
USER=$(whoami)
MIRROR="yum.opennms.org"
ANSWER="No"
RRDTOOL_VERSION=1.7.1

REQUIRED_SYSTEMS="CentOS|Red\\sHat"
REQUIRED_JDK="java-11-openjdk-devel"
RELEASE_FILE="/etc/redhat-release"

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
  echo "-r: Set a release: stable | testing | snapshot"
  echo "    Default: ${RELEASE}"
  echo "-m: Set alternative mirror server for packages"
  echo "    Default: ${MIRROR}"
  echo "-h: Show this help"
}

checkRequirements() {
  # Test if system is supported
  if ! grep -E "${REQUIRED_SYSTEMS}" "${RELEASE_FILE}" 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"; then
    echo ""
    echo "This is system is not a supported CentOS or Red Hat."
    echo ""
    exit "${E_UNSUPPORTED}"
  fi

  # Setting Postgres User and changing configuration files require
  # root permissions.
  if [[ "${USER}" != "${REQUIRED_USER}" ]]; then
    echo ""
    echo "This script requires root permissions to be executed."
    echo ""
    exit "${E_BASH}"
  fi

  # The sudo command is required to switch to postgres user for DB setup
  if ! command -v sudo 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"; then
    echo ""
    echo "This script requires sudo which could not be found."
    echo "Please install the sudo package."
    echo ""
    exit "${E_BASH}"
  fi

  # Test if a OpenJDK 11 Development Kit is installed
  if ! yum list installed | grep "${REQUIRED_JDK}" 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"; then
    echo ""
    echo "OpenNMS Horizon requires OpenJDK 11 Development Kit which is not"
    echo "available on your system. Please install OpenJDK 11 Development"
    echo "with:"
    echo ""
    echo "    yum install ${REQUIRED_JDK}"
    echo ""
    echo "Setup your system to use OpenJDK 11 JDK as your default and run the"
    echo "installer again. Hints how to setup your Java Environment can be"
    echo "found here: https://tinyurl.com/y4llkagl"
    echo ""
    exit "${E_BASH}"
  fi

  # When CentOS 8, then install RRDTool 1.7.0 from Appstream instead of OpenNMS repository
  if grep "CentOS Linux release 8" ${RELEASE_FILE}; then
    echo "CentOS 8 detected, set RRDTool version to 1.7.0 from Appstream."
    RRDTOOL_VERSION="1.7.0"
  fi
}

showDisclaimer() {
  echo ""
  echo "This script installsOpenNMS on your system with the following."
  echo "components:"
  echo ""
  echo " - PostgreSQL Server"
  echo " - OpenNMS Repositories"
  echo " - OpenNMS with core services and web application"
  echo " - Initializing and bootstrapping the database schema"
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
  read -r -p "If you want to proceed, type YES: " ANSWER

  # Set bash to case insensitive
  shopt -s nocasematch

  if [[ "${ANSWER}" == "yes" ]]; then
    echo ""
    echo "Starting setup procedure ... "
    echo ""
  else
    echo ""
    echo "Your system is unchanged."
    echo "Thank you computing with us"
    echo ""
    exit "${E_BASH}"
  fi

  # Set case sensitive
  shopt -u nocasematch
}

####
# The -r option is optional and allows to set the release of OpenNMS.
# The -m option allows to overwrite the package repository server.
while getopts r:m:h flag; do
  case "${flag}" in
    r)
        RELEASE="${OPTARG}"
        ;;
    m)
        MIRROR="${OPTARG}"
        ;;
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
  if [ "${1}" -eq 0 ]; then
    echo "OK"
  else
    echo "FAILED - Please check the bootstrap.log file for detailed error messages."
    exit "${E_BASH}"
  fi
}

####
# Install OpenNMS Debian repository for specific release
installOnmsRepo() {
  echo -n "Install OpenNMS Repository         ... "
  if [[ ! -f "/etc/yum.repos.d/opennms-repo-${RELEASE}-rhel7.repo" ]]; then
    rpm -Uvh "http://${MIRROR}/repofiles/opennms-repo-${RELEASE}-rhel7.noarch.rpm" 1>/dev/null 2>>${ERROR_LOG}
    checkError "${?}"

    echo -n "Install OpenNMS Repository Key     ... "
    rpm --import "http://${MIRROR}/OPENNMS-GPG-KEY" 2>>${ERROR_LOG}
    checkError "${?}"
  else
    echo "SKIP - file opennms-repo-${RELEASE}-rhel7.repo already exist"
  fi
}

####
# Install the OpenNMS application from Debian repository
installOnmsApp() {
  yum -y install rrdtool-${RRDTOOL_VERSION} jrrd2 opennms
  "${OPENNMS_HOME}"/bin/runjava -s 1>>"${ERROR_LOG}" 2>>${ERROR_LOG}
  checkError "${?}"
  clear
}

####
# Helper script to initialize the PostgreSQL database
initializePostgres() {
  echo -n "PostgreSQL initialize                 ... "
  postgresql-setup initdb 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"
  checkError "${?}"
  echo -n "PostgreSQL set auth from ident to md5 ... "
  sed -i 's/all             127\.0\.0\.1\/32            ident/all             127.0.0.1\/32            md5/g' /var/lib/pgsql/data/pg_hba.conf
  sed -i 's/all             ::1\/128                 ident/all             ::1\/128                 md5/g' /var/lib/pgsql/data/pg_hba.conf
  checkError "${?}"
  echo -n "Start PostgreSQL database             ... "
  systemctl start postgresql
  checkError "${?}"
  echo -n "PostgreSQL systemd enable             ... "
  systemctl enable postgresql 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"
  checkError "${?}"
}

####
# Helper to request Postgres credentials to initialize the
# OpenNMS database.
queryDbCredentials() {
  echo ""
  echo "Create credentials for the OpenNMS Horizon database"
  echo ""
  read -r -p "Create a username for the database : " DB_USER
  read -r -s -p "Set a password for database user   : " DB_PASS
  {
    sudo -i -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';"
    sudo -i -u postgres psql -c "CREATE DATABASE opennms;"
    sudo -i -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE opennms to ${DB_USER};"
  } 1>/dev/null
}

####
# Generate OpenNMS configuration file for accessing the PostgreSQL
# Database with credentials
setCredentials() {
  echo ""
  echo -n "Generate OpenNMS data source config   ... "
  if [[ -f "${OPENNMS_HOME}"/etc/opennms-datasources.xml ]]; then
    printf '<?xml version="1.0" encoding="UTF-8"?>
<datasource-configuration>
  <connection-pool factory="org.opennms.core.db.C3P0ConnectionFactory"
    idleTimeout="600"
    loginTimeout="3"
    minPool="50"
    maxPool="50"
    maxSize="50" />

  <jdbc-data-source name="opennms"
                    database-name="opennms"
                    class-name="org.postgresql.Driver"
                    url="jdbc:postgresql://localhost:5432/opennms"
                    user-name="%s"
                    password="%s" />

  <jdbc-data-source name="opennms-admin"
                    database-name="template1"
                    class-name="org.postgresql.Driver"
                    url="jdbc:postgresql://localhost:5432/template1"
                    user-name="%s"
                    password="%s" />
</datasource-configuration>' "${DB_USER}" "${DB_PASS}" "${DB_USER}" "${DB_PASS}" \
  > "${OPENNMS_HOME}"/etc/opennms-datasources.xml
  checkError "${?}"
  else
    echo "No OpenNMS configuration found in ${OPENNMS_HOME}/etc"
    exit "${E_ILLEGAL_ARGS}"
  fi
}

####
# Initialize the OpenNMS database schema
initializeOnmsDb() {
  echo -n "Initialize OpenNMS                    ... "
  if [[ ! -f "$OPENNMS_HOME"/etc/configured ]]; then
    "${OPENNMS_HOME}"/bin/install -dis 1>>"${ERROR_LOG}" 2>>${ERROR_LOG}
    checkError "${?}"
  else
    echo "SKIP - already configured"
  fi
}

restartOnms() {
  printf 'START_TIMEOUT=0' > "${OPENNMS_HOME}"/etc/opennms.conf
  echo -n "Starting OpenNMS                      ... "
  systemctl start opennms 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"
  checkError "${?}"
  echo -n "OpenNMS systemd enable                ... "
  systemctl enable opennms 1>>"${ERROR_LOG}" 2>>"${ERROR_LOG}"
  checkError "${?}"
}

# Execute setup procedure
clear
checkRequirements
showDisclaimer
installOnmsRepo
installOnmsApp
initializePostgres
queryDbCredentials
setCredentials
initializeOnmsDb
restartOnms

echo ""
echo "Congratulations"
echo "---------------"
echo ""
echo "OpenNMS is starting up and might take a few seconds." 
echo "By default CentOS 7 comes with a firewall enabled. You need to allow"
echo "port 8980/TCP to connect to the web application with"
echo ""
echo "  firewall-cmd --permanent --add-port=8980/tcp"
echo "  systemctl restart firewalld"
echo ""
echo "You should now be able to access the web application with"
echo ""
echo "  http://this-systems-ip:8980"
echo ""
echo "Login with username admin and password admin"
echo ""
echo "Please change immediately the password for your admin user!"
echo "Select in the main navigation \"Admin\" and go to \"Change Password\""
echo ""
echo "Thank you computing with us."
echo ""
