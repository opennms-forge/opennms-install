# Agent guide

Bootstrap scripts that install OpenNMS Horizon on DEB (Debian/Ubuntu) and RPM (EL9/EL10) systems.
Two entry points: `bootstrap-debian.sh` and `bootstrap-yum.sh`; shared test harness in `tests/integration-test.sh`.

## Commands

```bash
make lint                                              # shellcheck + actionlint
make integration-test IMAGE=debian:trixie SCRIPT=bootstrap-debian.sh
make integration-test IMAGE=almalinux:9 SCRIPT=bootstrap-yum.sh
```

A full integration test installs OpenNMS in a systemd container and takes 3-15 minutes.
CI (`integration-tests.yml`) runs lint plus an 8-distro matrix; branch protection requires the aggregate `Gate` check.

## Conventions

- Conventional Commits; every commit signed off (`git commit -s`) plus `Assisted-by: <Agent>:<model>` trailer for AI-assisted work (see CONTRIBUTING.md).
- PRs start from an issue and close it with `Closes #N`; merges are merge commits (squash/rebase disabled).
- Shell: bash with `set -eEuo pipefail`; step output pattern is `echo -n "label ... "` + `checkError "${?}"`; errors append to `bootstrap.log`.
- Actions are SHA-pinned with a full-semver comment; CI invokes make targets, never tools directly.

## Gotchas

- The scripts are interactive by default; CI and automation set `ONMS_UNATTENDED=yes` and pass `POSTGRES_PASS` (plus optional `DB_NAME`/`DB_USER`/`DB_PASS`) via environment.
- EL9 images ship `/etc/shadow` with mode 000; Ubuntu 24.04 hosts (GitHub runners) confine `unix_chkpwd` via AppArmor so sudo breaks unless the test image runs `chmod 0640 /etc/shadow` — do not remove that from the harness.
- OpenNMS `scvcli` uses the bashism `$(<java.conf)` under `#!/bin/sh` and breaks on dash; `bootstrap-debian.sh` must invoke it via `bash`.
- EL minimal images ship `curl-minimal`, which conflicts with `curl`; keep `--allowerasing`.
- Debian/Ubuntu library images have no systemd; the harness builds a throwaway image layering it in and boots with `--privileged --cgroupns=host`.
- `dnf config-manager` is unavailable on EL10 images (no dnf-plugins-core); the scripts fall back to sed on the repo file.
