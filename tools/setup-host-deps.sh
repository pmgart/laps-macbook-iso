#!/bin/bash
# ============================================================
# Återskapar värdberoenden för att kunna bygga ISO:n på en maskin
# som inte har ~/laps-debian-live kvar (t.ex. efter reinstall).
#
# Kör som vanlig användare:  bash tools/setup-host-deps.sh
# (apt-installationer skrivs ut som kommandon, körs inte automatiskt)
# ============================================================
set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
SCRATCH="$HOME/.hermes/cache/scratch"
EXPECTED_LB="3.0~a57-1ubuntu54"
EXPECTED_BLOB_SHA="7ec30d044a4bc52f35ac53c24aa75b56a8e7f892a8129c098e48467da069a143"

echo "== 1. Nödvändiga kommandon =="
MISSING=""
for t in lb debootstrap xorriso grub-mkstandalone mformat mmd mcopy unsquashfs 7z squashfs-tools; do
  command -v "$t" >/dev/null 2>&1 && printf '  ✅ %s\n' "$t" || { printf '  ❌ %s saknas\n' "$t"; MISSING="$MISSING $t"; }
done
if [ -n "$MISSING" ]; then
  echo "  → installera:  sudo apt install live-build debootstrap xorriso grub-efi-amd64-bin grub-pc-bin mtools squashfs-tools p7zip-full"
fi

echo "== 2. live-build-version =="
if command -v lb >/dev/null 2>&1; then
  LBV=$(dpkg-query -W -f='${Version}' live-build 2>/dev/null || lb --version 2>&1 | tail -1)
  echo "  installerad: $LBV (förväntad: $EXPECTED_LB)"
  [ "$LBV" = "$EXPECTED_LB" ] || echo "  ⚠️  annan version — de tre patcharna i fix-livebuild-*.sh kan träffa fel; kör dem och läs deras verifieringsrader"
fi

echo "== 3. MBR-blob (isohdpfx) =="
mkdir -p "$SCRATCH"
if [ -f "$REPO/tools/isohdpfx.bin" ]; then
  cp "$REPO/tools/isohdpfx.bin" "$SCRATCH/isohdpfx-laps.bin"
  GOT=$(sha256sum "$SCRATCH/isohdpfx-laps.bin" | cut -d' ' -f1)
  SZ=$(stat -c '%s' "$SCRATCH/isohdpfx-laps.bin")
  if [ "$SZ" = "432" ] && [ "$GOT" = "$EXPECTED_BLOB_SHA" ]; then
    echo "  ✅ $SCRATCH/isohdpfx-laps.bin (432 byte, sha256 OK)"
  else
    echo "  ❌ blob fel: $SZ byte, sha256 $GOT"
  fi
else
  echo "  ❌ tools/isohdpfx.bin saknas i repot"
fi

echo "== 4. Arbetskatalog =="
echo "  Skripten har hårdkodad sökväg /home/pablo-magana/laps-debian-live (BASE i add-efi-boot.py,"
echo "  absolut sökväg i resume-binary.sh). Klona där:"
echo "    git clone <repo-url> /home/pablo-magana/laps-debian-live"
