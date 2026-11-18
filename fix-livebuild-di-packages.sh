#!/bin/bash
# Fixar lb_binary_debian-installer DI-paket för Debian trixie:
# - gamla namn (lilo, grub, linux-image-2.6-*) finns inte i trixie
# - grub-pc och grub-efi-amd64 Conflicts med varandra (BIOS vs EFI)
#   -> MacBook8,1 är EFI-only: enbart grub-efi-amd64
# Idempotent; steg 1 från lilo-listan, steg 2 från kombinerade listan.
set -e
SCRIPT=/usr/lib/live/build/lb_binary_debian-installer
[ -f "$SCRIPT" ] || { echo "❌ $SCRIPT saknas"; exit 1; }

if grep -q 'DI_REQ_PACKAGES="grub-efi-amd64"' "$SCRIPT"; then
  echo "✅ Redan patchad (grub-efi-amd64 enbart) — inget att göra."
  exit 0
fi

cp -a "$SCRIPT" "${SCRIPT}.bak.$(date +%Y%m%d-%H%M%S)"

if grep -q 'DI_REQ_PACKAGES="grub-pc grub-efi-amd64"' "$SCRIPT"; then
  # Steg 2: kombinerad lista -> EFI enbart
  sed -i 's|DI_REQ_PACKAGES="grub-pc grub-efi-amd64"|DI_REQ_PACKAGES="grub-efi-amd64"|' "$SCRIPT"
else
  # Steg 1: original lilo-listan -> EFI enbart
  sed -i 's|DI_REQ_PACKAGES="lilo grub grub-pc"|DI_REQ_PACKAGES="grub-efi-amd64"|; s|DI_PACKAGES="${DI_REQ_PACKAGES} linux-image-2.6-amd64"|DI_PACKAGES="${DI_REQ_PACKAGES}"|' "$SCRIPT"
fi

if grep -q 'DI_REQ_PACKAGES="grub-efi-amd64"' "$SCRIPT"; then
  echo "✅ Patchad: DI-paket nu enbart grub-efi-amd64 (EFI-only, ingen grub-pc-konflikt)."
else
  echo "❌ Verifiering misslyckades"; exit 1
fi