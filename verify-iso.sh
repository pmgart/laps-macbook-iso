#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Verifierar den byggda ISO:n mot MacBook8,1-checklistan.
# Användning: bash verify-iso.sh [sökväg-till-iso]
set -u
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISO="$(ls "$BASE"/*.iso 2>/dev/null | head -1)"
[ -n "${1:-}" ] && ISO="$1"
[ -n "$ISO" ] && [ -f "$ISO" ] || { echo "❌ Ingen ISO hittad (bygg först, eller ange sökväg)"; exit 1; }
echo "ISO: $ISO ($(du -h "$ISO" | cut -f1))"
echo "SHA256: $(sha256sum "$ISO" | cut -d' ' -f1)"
echo

PASS=0; FAIL=0
check() { # $1=beskrivning $2=kommando
  if eval "$2" >/dev/null 2>&1; then echo "✅ $1"; PASS=$((PASS+1)); else echo "❌ $1"; FAIL=$((FAIL+1)); fi
}

# 1. GRUB-parametrar (efter isoinfo-innehåll: squashfs + grub.cfg)
MNT=$(mktemp -d /tmp/iso-verify.XXXXXX)
if sudo -n mount -o loop,ro "$ISO" "$MNT" 2>/dev/null; then
  MOUNTED=1
else
  echo "(loop-mount kräver sudo — använder 7z-extraktion istället)"
  EXTRACT=$(mktemp -d /tmp/iso-extract.XXXXXX)
  if command -v 7z >/dev/null; then 7z x -y -o"$EXTRACT" "$ISO" >/dev/null 2>&1;
  elif command -v bsdtar >/dev/null; then bsdtar -x -f "$ISO" -C "$EXTRACT" 2>/dev/null; fi
  MNT="$EXTRACT"
fi

check "GRUB live-meny innehåller initcall_blacklist=dw_pci_driver_init" \
  "grep -rqs 'initcall_blacklist=dw_pci_driver_init' $MNT/boot/grub/ $MNT/boot/live/"
check "Installer-kärna (vmlinuz) finns i ISO" "ls $MNT/install.* >/dev/null 2>&1 || find $MNT -name 'vmlinuz*' | grep -q ."
check "Live-squashfs finns" "find $MNT -name 'filesystem.squashfs' | grep -q ."
check "EFI-boot: boot/grub/efi.img finns" "test -f $MNT/boot/grub/efi.img"
check "EFI-boot: EFI/boot/bootx64.efi finns" "test -f $MNT/EFI/boot/bootx64.efi"

SQUASH=$(find $MNT -name 'filesystem.squashfs' | head -1)
if [ -n "$SQUASH" ] && command -v unsquashfs >/dev/null; then
  SQ=$(mktemp -d /tmp/sq-verify.XXXXXX)
  unsquashfs -n -d "$SQ" "$SQUASH" \
    /opt/macbook8-1-debian-guide/README.md \
    /usr/local/bin/laps-macbook-setup \
    /etc/X11/Xsession.d/95mb81-swedish-keys >/dev/null 2>&1
  check "Guide-repo bakat in i squashfs (/opt/macbook8-1-debian-guide)" "test -f $SQ/opt/macbook8-1-debian-guide/README.md"
  check "Setup-meny i squashfs (/usr/local/bin/laps-macbook-setup)" "test -x $SQ/usr/local/bin/laps-macbook-setup"
  check "Svensk §/<>-tangentbordsfix i squashfs" "test -f $SQ/etc/X11/Xsession.d/95mb81-swedish-keys"
  rm -rf "$SQ"
else
  echo "⚠️  Kan inte öppna squashfs (unsquashfs saknas?) — kontrollera manuellt"
fi

[ -n "${MOUNTED:-}" ] && sudo -n umount "$MNT" 2>/dev/null
rm -rf "$MNT" 2>/dev/null
echo
echo "RESULTAT: $PASS ✅ / $FAIL ❌"
if [ "$FAIL" -eq 0 ]; then
  echo "🎉 ISO verifierad — klar för flashning (BalenaEtcher / dd)"
else
  echo "⚠️  Åtgärda felen innan flashning"
  exit 1
fi
