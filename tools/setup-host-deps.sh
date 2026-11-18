#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# ============================================================
# Kontrollerar värdberoenden för ISO-bygget och lägger MBR-blobben på plats.
# Körs som vanlig användare:  bash tools/setup-host-deps.sh
# (apt-installationer skrivs ut som kommandon, körs aldrig automatiskt)
# ============================================================
set -u
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_LB="3.0~a57-1ubuntu54"
EXPECTED_BLOB_SHA="7ec30d044a4bc52f35ac53c24aa75b56a8e7f892a8129c098e48467da069a143"

echo "== 1. Nödvändiga kommandon =="
MISSING=""
for t in lb debootstrap xorriso grub-mkimage grub-mkstandalone grub-fstest \
         mformat mmd mcopy unsquashfs 7z; do
  if command -v "$t" >/dev/null 2>&1; then
    printf '  ✅ %s\n' "$t"
  else
    printf '  ❌ %s saknas\n' "$t"; MISSING="$MISSING $t"
  fi
done
if [ -n "$MISSING" ]; then
  echo "  → sudo apt install live-build debootstrap xorriso grub-efi-amd64-bin grub-common \\"
  echo "                    mtools squashfs-tools p7zip-full"
fi

echo "== 2. live-build-version =="
if command -v lb >/dev/null 2>&1; then
  LBV=$(dpkg-query -W -f='${Version}' live-build 2>/dev/null || lb --version 2>&1 | tail -1)
  echo "  installerad: $LBV (förväntad: $EXPECTED_LB)"
  [ "$LBV" = "$EXPECTED_LB" ] || echo "  ⚠️  annan version — de tre fix-livebuild-*.sh kan träffa fel; kör dem och läs deras verifieringsrader"
fi

echo "== 3. MBR-blob (isohdpfx, 432 byte) =="
if [ -f "$BASE/tools/isohdpfx.bin" ]; then
  GOT=$(sha256sum "$BASE/tools/isohdpfx.bin" | cut -d' ' -f1)
  SZ=$(stat -c '%s' "$BASE/tools/isohdpfx.bin")
  if [ "$SZ" = "432" ] && [ "$GOT" = "$EXPECTED_BLOB_SHA" ]; then
    echo "  ✅ tools/isohdpfx.bin (432 byte, sha256 OK) — används direkt av add-efi-boot.py"
  else
    echo "  ❌ blob fel: $SZ byte, sha256 $GOT"
  fi
else
  echo "  ❌ tools/isohdpfx.bin saknas — återskapa från en känd bra ISO:"
  echo "     dd if=/path/to/verified.iso of=tools/isohdpfx.bin bs=432 count=1"
fi

echo "== 4. Repo-placering =="
echo "  Bygget sker i den här katalogen: $BASE"
echo "  Alla skript räknar ut sin egen sökväg, så katalogen kan heta vad som helst."
