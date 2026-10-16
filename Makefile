PREFIX ?= $(HOME)/.local
SCRIPTS = bin/afar-rcd install.sh test/run.sh test/fake-claude

.PHONY: check lint test install uninstall

check: lint test

lint:
	shellcheck -x $(SCRIPTS)
	/bin/bash -n bin/afar-rcd

test:
	test/run.sh

install:
	AFAR_RCD_PREFIX=$(PREFIX) ./install.sh

uninstall:
	AFAR_RCD_PREFIX=$(PREFIX) ./install.sh --uninstall
