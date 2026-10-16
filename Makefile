# Copyright 2026 Ronny Trommer <ronny@no42.org>
# SPDX-License-Identifier: GPL-3.0-or-later

IMAGE ?= debian:trixie
SCRIPT ?= bootstrap-debian.sh

.PHONY: lint
lint:
	shellcheck -S warning bootstrap-debian.sh bootstrap-yum.sh tests/integration-test.sh tests/check-versions.sh tests/check-mirrors.sh
	actionlint
	tests/check-versions.sh

.PHONY: check-mirrors
check-mirrors:
	tests/check-mirrors.sh

.PHONY: integration-test
integration-test:
	tests/integration-test.sh "$(IMAGE)" "$(SCRIPT)"
