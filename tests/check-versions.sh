#!/usr/bin/env bash
#
# Copyright 2026 Ronny Trommer <ronny@no42.org>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Fail when the README badges disagree with the version constants in the
# bootstrap scripts: the certified combo must be stated truthfully.

set -euo pipefail

fail=0
for script in bootstrap-debian.sh bootstrap-yum.sh; do
  onms=$(sed -n 's/^ONMS_VERSION=//p' "${script}")
  psql=$(sed -n 's/^PSQL_VERSION=//p' "${script}")
  if ! grep -qF "OpenNMS_Horizon-${onms}-" README.md; then
    echo "README Horizon badge does not show ${onms} (ONMS_VERSION in ${script})" >&2
    fail=1
  fi
  if ! grep -qF "PostgreSQL-${psql}-" README.md; then
    echo "README PostgreSQL badge does not show ${psql} (PSQL_VERSION in ${script})" >&2
    fail=1
  fi
done
exit "${fail}"
