#!/bin/bash -e
# Script to bootstrap a basic OpenNMS setup

# Default build identifier set to snapshot
RELEASE="stable"
ERROR_LOG="bootstrap.log"
DB_USER="opennms"
DB_PASS="opennms"
OPENNMS_HOME="/opt/opennms"
REQUIRED_USER="root"
USER=$(whoami)
MIRROR="yum.mirrors.opennms.org"
ANSWER="No"

REQUIRED_SYSTEMS="CentOS|Red\sHat"
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

showDisclaimer() {
  echo ""
  echo "This script installs OpenNMS on  your system. It will"
  echo "install  all  components necessary  to  run  OpenNMS."
  echo ""
  echo "The following components will be installed:"
  echo ""
  echo " - Oracle Java 8 JDK"
  echo " - PostgreSQL Server"
  echo " - OpenNMS Repositories"
  echo " - OpenNMS with core services and Webapplication"
  echo " - Initialize and bootstrapping the database"
  echo " - Start OpenNMS"
  echo ""
  echo "If you have OpenNMS already installed, don't use this"
  echo "script!"
  echo ""
  read -p "If you want to proceed, type YES: " ANSWER

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
    exit ${E_BASH}
  fi

  # Set case sensitive
  shopt -u nocasematch
}

# Test if system is supported
cat ${RELEASE_FILE} | grep -E ${REQUIRED_SYSTEMS}  1>/dev/null 2>>${ERROR_LOG}
if [ ! ${?} -eq 0 ]; then
  echo ""
  echo "This is system is not a supported CentOS or Red Hat."
  echo ""
  exit ${E_UNSUPPORTED}
fi

# Setting Postgres User and changing configuration files require
# root permissions.
if [ "${USER}" != "${REQUIRED_USER}" ]; then
  echo ""
  echo "This script requires root permissions to be executed."
  echo ""
  exit ${E_BASH}
fi

####
# The -r option is optional and allows to set the release of OpenNMS.
# The -m option allows to overwrite the package repository server.
while getopts r:m:h flag; do
  case ${flag} in
    r)
        RELEASE="${OPTARG}"
        ;;
    m)
        MIRROR="${OPTARG}"
        ;;
    h)
      usage
      exit ${E_ILLEGAL_ARGS}
      ;;
    *)
      usage
      exit ${E_ILLEGAL_ARGS}
      ;;
  esac
done

####
# Helper function which tests if a command was successful or failed
checkError() {
  if [ $1 -eq 0 ]; then
    echo "OK"
  else
    echo "FAILED"
    exit ${E_BASH}
  fi
}

####
# Install OpenNMS Debian repository for specific release
installOnmsRepo() {
  echo -n "Install OpenNMS Repository         ... "
  if [ ! -f /etc/yum.repos.d/opennms-repo-${RELEASE}-rhel7.repo ]; then
    rpm -Uvh http://${MIRROR}/repofiles/opennms-repo-${RELEASE}-rhel7.noarch.rpm 1>/dev/null 2>>${ERROR_LOG}
    checkError ${?}

    echo -n "Install OpenNMS Repository Key     ... "
    rpm --import http://${MIRROR}/OPENNMS-GPG-KEY 1 >/dev/null 2>>${ERROR_LOG}
    checkError ${?}
  else
    echo "SKIP - file opennms-repo-${RELEASE}-rhel7.repo already exist"
  fi
}

####
# Install the OpenNMS application from Debian repository
installOnmsApp() {
  yum -y install opennms
  ${OPENNMS_HOME}/bin/runjava -s 1>/dev/null 2>>${ERROR_LOG}
  checkError ${?}
  clear
}

####
# Helper to request Postgres credentials to initialize the
# OpenNMS database.
queryDbCredentials() {
  echo ""
  echo "PostgreSQL credentials for OpenNMS"
  read -p "Enter username: " DB_USER
  read -s -p "Enter password: " DB_PASS
  echo "PostgreSQL initialize                 ... "
  postgresql-setup initdb 1>/dev/null 2>>${ERROR_LOG}
  checkError ${?}
  echo "PostgreSQL auth from ident to md5     ... "
  echo "host    all             all             127.0.0.1/32            md5" >> /var/lib/pgsql/data/pg_hba.conf
  echo "host    all             all             ::1/128                 md5" >> /var/lib/pgsql/data/pg_hba.conf
  checkError ${?}
  echo "PostgreSQL systemd enable             ... "
  systemctl enable postgresql 1>/dev/null 2>>${ERROR_LOG}
  checkError ${?}
  echo "Start PostgreSQL database             ... "
  systemctl start postgresql
  checkError ${?}
  sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';" 1>/dev/null 2>>${ERROR_LOG}
  sudo -u postgres psql -c "CREATE DATABASE opennms;" 1>/dev/null 2>>${ERROR_LOG}
  sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE opennms to ${DB_USER};" 1>/dev/null 2>>${ERROR_LOG}
}

####
# Generate OpenNMS configuration file for accessing the PostgreSQL
# Database with credentials
setCredentials() {
  echo ""
  echo -n "Generate OpenNMS data source config   ... "
  if [ -f "${OPENNMS_HOME}/etc/opennms-datasources.xml" ]; then
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
</datasource-configuration>' ${DB_USER} ${DB_PASS} ${DB_USER} ${DB_PASS} \
  > ${OPENNMS_HOME}/etc/opennms-datasources.xml
  checkError ${?}
  else
    echo "No OpenNMS configuration found in ${OPENNMS_HOME}/etc"
    exit ${E_ILLEGAL_ARGS}
  fi
}

####
# Initialize the OpenNMS database schema
initializeOnmsDb() {
  echo -n "Initialize OpenNMS                    ... "
  if [ ! -f $OPENNMS_HOME/etc/configured ]; then
    ${OPENNMS_HOME}/bin/install -dis 1>/dev/null 2>>${ERROR_LOG}
    checkError ${?}
  else
    echo "SKIP - already configured"
  fi
}

restartOnms() {
  echo -n "Starting OpenNMS                      ... "
  systemctl start opennms 1>/dev/null 2>>${ERROR_LOG}
  checkError ${?}
  echo -n "OpenNMS systemd enable                ... "
  systemctl enable opennms 1>/dev/null 2>>${ERROR_LOG}
  checkError ${?}
}

# Execute setup procedure
clear
showDisclaimer
installOnmsRepo
installOnmsApp
queryDbCredentials
setCredentials
initializeOnmsDb
restartOnms

echo ""
echo "Congratulations"
echo "---------------"
echo ""
echo "OpenNMS is up and running. You can access the web application with"
echo ""
echo "http://this-systems-ip:8980"
echo ""
echo "Login with username admin and password admin"
echo ""
echo "Please change immediately the password for your admin user!"
echo "Select in the main navigation \"Admin\" and go to \"Change Password\""
echo ""
echo "Thank you computing with us."
echo ""
