#!/usr/bin/env bash
#
# Copyright 2026 Ronny Trommer <ronny@no42.org>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Fail when a regional package mirror does not publish the pinned
# ONMS_VERSION. CI runners resolve the repo hostnames to the US mirror, so a
# lagging EU mirror is otherwise invisible. Each request is sent to a given
# mirror host while keeping the repo hostname for TLS and the vhost.

set -euo pipefail

MIRRORS=(europe.mirrors.opennms.org na.mirrors.opennms.org)

# pinned <deb|yum>: ONMS_VERSION from the matching bootstrap script
pinned() {
  case "${1}" in
    deb) sed -n 's/^ONMS_VERSION=//p' bootstrap-debian.sh ;;
    yum) sed -n 's/^ONMS_VERSION=//p' bootstrap-yum.sh ;;
  esac
}

# fetch <mirror> <url>: GET url from the given mirror host
fetch() {
  local host=${2#https://}
  host=${host%%/*}
  curl -sSfL --retry 3 --connect-to "${host}:443:${1}:443" "${2}"
}

# decompress <file name>: pick the decompressor from the metadata file suffix
decompress() {
  case "${1}" in
    *.gz) gunzip -c ;;
    *.zst) zstd -dc ;;
    *.xz) xz -dc ;;
    *) cat ;;
  esac
}

deb_versions() {
  fetch "${1}" https://debian.opennms.org/dists/stable/main/binary-amd64/Packages.gz \
    | gunzip -c \
    | awk '/^Package: /{p=($2=="opennms")} p&&/^Version: /{sub(/-[^-]*$/,"",$2); print $2}'
}

yum_versions() {
  local base=https://yum.opennms.org/stable/common primary
  primary=$(fetch "${1}" "${base}/repodata/repomd.xml" | grep -o 'repodata/[^"]*-primary\.xml[^"]*')
  fetch "${1}" "${base}/${primary}" \
    | decompress "${primary}" \
    | grep -A3 '<name>opennms-core</name>' \
    | sed -n 's/.*<version [^>]* ver="\([^"]*\)".*/\1/p'
}

fail=0
for mirror in "${MIRRORS[@]}"; do
  for repo in deb yum; do
    pin=$(pinned "${repo}")
    if ! versions=$("${repo}_versions" "${mirror}"); then
      echo "FAIL ${mirror} ${repo}: metadata not reachable" >&2
      fail=1
    elif grep -qxF "${pin}" <<<"${versions}"; then
      echo "OK   ${mirror} ${repo}: ${pin}"
    else
      newest=$(sort -V <<<"${versions}" | tail -1)
      echo "FAIL ${mirror} ${repo}: newest ${newest:-none}, pinned ${pin}" >&2
      fail=1
    fi
  done
done
exit "${fail}"
