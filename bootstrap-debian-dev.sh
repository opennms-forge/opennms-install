#!/bin/bash -e
# Script to bootstrap a basic OpenNMS development environment

# Default build identifier set to snapshot
RELEASE="stable"
ERROR_LOG="bootstrap-dev.log"
DB_USER="opennms"
DB_PASS="opennms"
OPENNMS_HOME="/usr/share/opennms"
REQUIRED_USER="root"
USER=$(whoami)
MIRROR="debian.mirrors.opennms.org"
ANSWER="No"

REQUIRED_SYSTEMS="Ubuntu|Debian"
RELEASE_FILE="/etc/issue"

# Error codes
E_ILLEGAL_ARGS=126
E_BASH=127
E_UNSUPPORTED=128

####
# Help function used in error messages and -h option
usage() {
  echo ""
  echo "Bootstrap OpenNMS development environment."
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
  echo "install  all  components necessary  to  develop  with"
  echo "OpenNMS."
  echo ""
  echo "The following components will be installed:"
  echo ""
  echo " - Oracle Java 8 JDK"
  echo " - OpenNMS Repositories"
  echo " - Install git-core, nsis, maven, jicmp, jicmp6, jrrd"
  echo " - Initialize and bootstrapping the Postgres database"
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
    echo "Thank you computing with us!"
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
  echo "This is system is not a supported Ubuntu or Debian system."
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
  if [ ! -f /etc/apt/sources.list.d/opennms-${RELEASE}.list ]; then
    printf "deb http://${MIRROR} ${RELEASE} main\ndeb-src http://${MIRROR} ${RELEASE} main" \
           > /etc/apt/sources.list.d/opennms-${RELEASE}.list
    checkError ${?}

    echo -n "Install OpenNMS Repository Key     ... "
    wget -q -O - http://${MIRROR}/OPENNMS-GPG-KEY | sudo apt-key add - 1>/dev/null 2>>${ERROR_LOG}
    checkError ${?}

    echo -n "Update repository                  ... "
    apt-get update 1>/dev/null 2>>${ERROR_LOG}
    checkError ${?}
  else
    echo "SKIP - file opennms-${RELEASE}.list already exist"
  fi
}

installOracleJdk() {
  echo -n "Install Oracle Java Repository     ... "
  add-apt-repository -y ppa:webupd8team/java 1>/dev/null 2>>${ERROR_LOG}
  checkError ${?}

  echo -n "Update Repository                  ... "
  apt-get update 1>/dev/null 2>>${ERROR_LOG}
  checkError ${?}

  echo -n "Install Oracle Java installer      ... "
  apt-get install -y oracle-java8-installer 1>/dev/null 2>>${ERROR_LOG}
  checkError ${?}

  echo -n "Set Oracle Java as default         ... "
  apt-get install -y oracle-java8-set-default 1>/dev/null 2>>${ERROR_LOG}
  checkError ${?}
}

installPostgres() {
  echo -n "Install PostgreSQL database        ... "
  apt-get install -y postgresql 1>/dev/null 2>>${ERROR_LOG}
  checkError ${?}

  echo -n "PostgreSQL set auth from md5 to trust ... "
  sed -i 's/all             127\.0\.0\.1\/32            md5/all             127.0.0.1\/32            trust/g' /etc/postgresql/9.3/main/pg_hba.conf
  sed -i 's/all             ::1\/128                 md5/all             ::1\/128                 trust/g' /etc/postgresql/9.3/main/pg_hba.conf
  checkError ${?}

  echo -n "Restart PostgreSQL database           ... "
  service postgresql restart 1>/dev/null 2>>${ERROR_LOG}
  checkError ${?}
}

####
# Install required tools
installTools() {
  echo ""
  echo -n "Install software-propertes-common  ... "
  apt-get install -y software-properties-common 1>/dev/null 2>>${ERROR_LOG}
  checkError ${?}

  echo -n "Install git-core                   ... "
  apt-get install -y git-core 1>/dev/null 2>>${ERROR_LOG}
  checkError ${?}

  echo -n "Install nsis                       ... "
  apt-get install -y nsis 1>/dev/null 2>>${ERROR_LOG}
  checkError ${?}

  echo -n "Install maven                      ... "
  apt-get install -y maven 1>/dev/null 2>>${ERROR_LOG}
  checkError ${?}

  echo -n "Install jicmp                      ... "
  apt-get install -y jicmp 1>/dev/null 2>>${ERROR_LOG}
  checkError ${?}

  echo -n "Install jicmp6                     ... "
  apt-get install -y jicmp6 1>/dev/null 2>>${ERROR_LOG}
  checkError ${?}
}

# Execute setup procedure
clear
showDisclaimer
installOnmsRepo
installOracleJdk
installPostgres
installTools

echo ""
echo "Congratulations"
echo "---------------"
echo ""
echo "Your system is prepared to develop with OpenNMS."
echo "Get the source code from, e.g."
echo ""
echo "git clone https://github.com/OpenNMS/opennms.git ~/dev/opennms"
echo ""
echo "Compile and assemble OpenNMS in this example:"
echo ""
echo "cd  ~/dev/opennms:"
echo "./clean.pl"
echo "./compile.pl -DskipTests"
echo "./assemble -p dir"
echo ""
echo "Thank you computing with us."
echo ""
