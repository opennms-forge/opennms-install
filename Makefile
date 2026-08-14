# Copyright 2026 Ronny Trommer <ronny@no42.org>
# SPDX-License-Identifier: GPL-3.0-or-later

IMAGE ?= debian:trixie
SCRIPT ?= bootstrap-debian.sh

.PHONY: lint
lint:
	shellcheck -S warning bootstrap-debian.sh bootstrap-yum.sh tests/integration-test.sh tests/check-versions.sh
	actionlint
	tests/check-versions.sh

.PHONY: integration-test
integration-test:
	tests/integration-test.sh "$(IMAGE)" "$(SCRIPT)"
