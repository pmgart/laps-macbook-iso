# SPDX-License-Identifier: GPL-3.0-or-later
# Build the LAPS Debian MacBook8,1 ISO. Run `make` for the target list.
SHELL := /bin/bash
REPO  := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

.DEFAULT_GOAL := help
.PHONY: help deps patches build resume efi verify qemu lint clean distclean

help: ## Visa denna hjälp
	@echo "LAPS Debian MacBook8,1 ISO — bygga, verifiera, städa"
	@echo
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | awk -F':.*?## ' '{printf "  make %-10s %s\n", $$1, $$2}'
	@echo
	@echo "Första gången:  make deps && make build   (sedan: make efi && make verify)"

deps: ## Kontrollera värdberoenden (live-build, xorriso, mtools, MBR-blob)
	@bash "$(REPO)/tools/setup-host-deps.sh"

patches: deps ## Patched live-build (kräver sudo) — körs även av make build
	@sudo bash "$(REPO)/fix-livebuild-contents.sh"
	@sudo bash "$(REPO)/fix-livebuild-di-packages.sh"
	@sudo bash "$(REPO)/fix-livebuild-trixie-data.sh"

build: ## Fullt bygge i bakgrunden (~40 min, kräver sudo)
	@bash "$(REPO)/build-laps-debian.sh"

resume: ## Återuppta från binärstadiet (~10 min, kräver sudo + befintlig chroot)
	@bash "$(REPO)/resume-binary.sh"

efi: ## Lägg EFI-boot i ISO:n (obligatoriskt steg efter lb binary)
	@python3 "$(REPO)/add-efi-boot.py"

verify: ## Verifiera ISO:n mot checklistan
	@bash "$(REPO)/verify-iso.sh"

qemu: ## QEMU EFI-boot-test av ISO:n (150 s)
	@bash "$(REPO)/qemu-test-laps-iso.sh"

lint: ## ShellCheck + Python-syntax
	@bash -n *.sh tools/*.sh && echo "✅ bash -n OK"
	@command -v shellcheck >/dev/null && shellcheck -x -S warning *.sh tools/*.sh && echo "✅ shellcheck OK" || echo "⚠️  shellcheck saknas (apt install shellcheck)"
	@python3 -m py_compile add-efi-boot.py make-efi-img.py && echo "✅ python OK"

clean: ## Ta bort chroot + cache (behåller ISO:n)
	@sudo lb clean --purge && echo "✅ chroot/cache borta — ISO:n är orörd"

distclean: ## Ta bort även byggd ISO och loggar (oåterkalleligt)
	@sudo lb clean --purge
	@rm -f "$(REPO)"/*.iso "$(REPO)"/*.iso.sha256 "$(REPO)"/build.log "$(REPO)"/build-status.log
	@echo "✅ allt byggt är borta"
