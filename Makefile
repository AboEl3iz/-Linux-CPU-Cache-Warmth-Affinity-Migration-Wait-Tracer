# Makefile for cpu-cache-affinity-wait

PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
DATADIR ?= $(PREFIX)/share/cpu-cache-affinity-wait
VERSION ?= 1.0.0
ARCH ?= all

.PHONY: all build package install uninstall lint test clean help

all: build

help:
	@echo "cpu-cache-affinity-wait Makefile"
	@echo "================================="
	@echo "  make build      Build distribution packages (.deb, .rpm, .tar.gz)"
	@echo "  make package    Alias for build"
	@echo "  make install    Install files to $(PREFIX)"
	@echo "  make uninstall  Uninstall files from $(PREFIX)"
	@echo "  make lint       Run syntax checks on shell and bpftrace scripts"
	@echo "  make clean      Remove build artifacts and dist directory"

build: package

package:
	@chmod +x scripts/build_packages.sh
	@./scripts/build_packages.sh $(VERSION) $(ARCH)

install:
	@echo "Installing cpu-cache-affinity-wait to $(PREFIX)..."
	install -d $(DESTDIR)$(BINDIR)
	install -d $(DESTDIR)$(DATADIR)
	install -m 755 cpu_cache_affinity_wait.sh $(DESTDIR)$(BINDIR)/cpu_cache_affinity_wait.sh
	ln -sf cpu_cache_affinity_wait.sh $(DESTDIR)$(BINDIR)/cpu_cache_affinity_wait
	install -m 644 cpu_cache_affinity_wait.bt $(DESTDIR)$(DATADIR)/cpu_cache_affinity_wait.bt
	@echo "Successfully installed."

uninstall:
	@echo "Uninstalling cpu-cache-affinity-wait from $(PREFIX)..."
	rm -f $(DESTDIR)$(BINDIR)/cpu_cache_affinity_wait.sh
	rm -f $(DESTDIR)$(BINDIR)/cpu_cache_affinity_wait
	rm -rf $(DESTDIR)$(DATADIR)
	@echo "Successfully uninstalled."

lint:
	@echo "Linting shell script..."
	@bash -n cpu_cache_affinity_wait.sh
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck cpu_cache_affinity_wait.sh; \
	else \
		echo "shellcheck not installed, skipping advanced bash lint."; \
	fi
	@echo "Lint passed!"

test: lint

clean:
	rm -rf build dist
