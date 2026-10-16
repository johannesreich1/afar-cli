PREFIX ?= $(HOME)/.local
SCRIPTS = bin/afar-rcd install.sh test/run.sh test/fake-claude

.PHONY: check lint test install uninstall

check: lint test

lint:
	shellcheck -x $(SCRIPTS)
	/bin/bash -n bin/afar-rcd
	@# Files .gitignore excludes (such as AI assistant files) must not be committed, even with git add -f.
	@files=$$(git ls-files -ci --exclude-standard); \
	if [ -n "$$files" ]; then printf 'error: tracked files that .gitignore excludes:\n%s\n' "$$files" >&2; exit 1; fi

test:
	test/run.sh

install:
	AFAR_RCD_PREFIX=$(PREFIX) ./install.sh

uninstall:
	AFAR_RCD_PREFIX=$(PREFIX) ./install.sh --uninstall
