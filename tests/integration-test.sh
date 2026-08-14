#!/usr/bin/env bash
#
# Copyright 2026 Ronny Trommer <ronny@no42.org>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Run a bootstrap script unattended inside a systemd container and verify
# the OpenNMS installation. Used by CI and for local reproduction:
#
#   tests/integration-test.sh debian:trixie bootstrap-debian.sh
#   tests/integration-test.sh almalinux:9 bootstrap-yum.sh

set -euo pipefail

IMAGE="${1:?Usage: ${0} <image> <bootstrap-script>}"
SCRIPT="${2:?Usage: ${0} <image> <bootstrap-script>}"
# Unique container name so concurrent runs (e.g. deb and rpm in parallel)
# do not collide; one test image per script family to reuse the build cache.
CONTAINER="opennms-install-test-$$"
TEST_IMAGE="opennms-install-test-${SCRIPT%.sh}"

# The plain distribution images do not ship everything a real host has:
# systemd (Debian/Ubuntu images boot without it), sudo and lsb-release are
# hard requirements of the bootstrap scripts, and hostname provides
# "hostname -I" used to determine the IP address on EL.
case "${SCRIPT}" in
  bootstrap-debian.sh)
    PREREQS="apt-get update && apt-get install -y systemd systemd-sysv sudo lsb-release && apt-get clean"
    PG_SERVICE="postgresql"
    # shellcheck disable=SC2016
    DS_VERIFY='pkg="$(dpkg -S /opt/opennms/etc/opennms-datasources.xml | cut -d: -f1)"; ! dpkg --verify "${pkg}" | grep datasources'
    ;;
  bootstrap-yum.sh)
    # chmod /etc/shadow: EL ships it with mode 0000, so unix_chkpwd needs
    # CAP_DAC_OVERRIDE, which the Ubuntu host's AppArmor unix-chkpwd profile
    # denies inside containers and sudo fails with a PAM error. Mode 0640
    # lets root read it without the capability.
    PREREQS="dnf install -y systemd sudo hostname && dnf clean all && chmod 0640 /etc/shadow"
    # The EL unit name carries the version; derive it from the script so a
    # version bump there cannot drift from this check.
    PG_SERVICE="postgresql-$(sed -n 's/^PSQL_VERSION=//p' bootstrap-yum.sh)"
    DS_VERIFY='! rpm -Vf /opt/opennms/etc/opennms-datasources.xml | grep datasources'
    ;;
  *)
    echo "Unknown bootstrap script: ${SCRIPT}" >&2
    exit 1
    ;;
esac

cleanup() {
  status="${?}"
  if [[ "${status}" -ne 0 ]]; then
    echo "=== Installer log ==="
    docker exec "${CONTAINER}" cat /workspace/bootstrap.log 2>/dev/null || true
    echo "=== Systemd journal ==="
    docker exec "${CONTAINER}" journalctl -n 200 --no-pager 2>/dev/null || true
  fi
  docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
  exit "${status}"
}
trap cleanup EXIT

echo "== Build test image from ${IMAGE}"
docker build -t "${TEST_IMAGE}" - <<EOF
FROM ${IMAGE}
RUN ${PREREQS}
CMD ["/sbin/init"]
EOF

echo "== Launch systemd container"
docker run -d \
  --name "${CONTAINER}" \
  --privileged \
  --cgroupns=host \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  --tmpfs /tmp --tmpfs /run --tmpfs /run/lock \
  "${TEST_IMAGE}" /sbin/init

echo "== Copy installer into container"
docker exec "${CONTAINER}" mkdir -p /workspace
docker cp . "${CONTAINER}:/workspace/"

echo "== Run ${SCRIPT}"
# Custom database identifiers, all distinct from the stock defaults in the
# Horizon datasources file (opennms/postgres), so a silent fallback to the
# defaults cannot pass the install.
docker exec \
  -e ONMS_UNATTENDED=yes \
  -e POSTGRES_PASS=bootstrap-ci \
  -e DB_NAME=horizon \
  -e DB_USER=horizon \
  -e DB_PASS=bootstrap-ci-db \
  "${CONTAINER}" bash -c "cd /workspace && bash ${SCRIPT}"

echo "== Verify installation"
echo -n "PostgreSQL service: "
docker exec "${CONTAINER}" systemctl is-active "${PG_SERVICE}"
echo -n "OpenNMS service: "
docker exec "${CONTAINER}" systemctl is-active opennms
docker exec "${CONTAINER}" curl -f -s -o /dev/null -w "Web UI HTTP status: %{http_code}\n" http://localhost:8980/opennms/
echo -n "Packaged datasources file pristine: "
docker exec "${CONTAINER}" bash -c "${DS_VERIFY}" && echo "yes"
echo -n "OPENNMS_DBNAME export in opennms.conf: "
docker exec "${CONTAINER}" grep -c 'export OPENNMS_DBNAME="horizon"' /opt/opennms/etc/opennms.conf
