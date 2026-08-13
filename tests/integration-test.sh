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
    ;;
  bootstrap-yum.sh)
    PREREQS="dnf install -y systemd sudo hostname && dnf clean all"
    # The EL unit name carries the version; derive it from the script so a
    # version bump there cannot drift from this check.
    PG_SERVICE="postgresql-$(sed -n 's/^PSQL_MAX_VERSION=//p' bootstrap-yum.sh)"
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
docker exec \
  -e ONMS_UNATTENDED=yes \
  -e POSTGRES_PASS=bootstrap-ci \
  "${CONTAINER}" bash -c "cd /workspace && bash ${SCRIPT}"

echo "== Verify installation"
echo -n "PostgreSQL service: "
docker exec "${CONTAINER}" systemctl is-active "${PG_SERVICE}"
echo -n "OpenNMS service: "
docker exec "${CONTAINER}" systemctl is-active opennms
docker exec "${CONTAINER}" curl -f -s -o /dev/null -w "Web UI HTTP status: %{http_code}\n" http://localhost:8980/opennms/
