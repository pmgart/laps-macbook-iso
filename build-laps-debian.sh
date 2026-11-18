#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# ============================================================
# LAPS MacBook Debian — ISO builder (trixie, 4 desktops)
#
# Builds a live+installer ISO with Cinnamon/XFCE/KDE/Sway + SDDM,
# Broadcom WiFi firmware, Swedish keyboard layout, the MacBook8,1
# SPI fix (GRUB parameter in every boot phase), the guide repo and
# the gated `laps-macbook-setup` menu.
#
# Requires sudo (once, for lb). Runs the build detached in the
# background; .build-done is written ONLY on a successful build.
#
# After this script:  python3 add-efi-boot.py  &&  bash verify-iso.sh
# ============================================================
set -u
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$BASE" || exit 1

echo "🚀 LAPS Debian 4-DE — bygger Trixie-ISO i $BASE"

# --- Patch 0: live-build skriver /updates för security-suiten, trixie heter -security
echo "🔧 Patcher live-build security-suite (trixie-security)..."
sudo sed -i 's|}/updates|}-security|g' /usr/lib/live/build/lb_chroot_archives || true

# --- Patch 1: Contents-<arch>.gz ligger per komponent i trixie
echo "🔧 Patcher live-build Contents-URL (trixie per-komponent)..."
sudo bash "$BASE/fix-livebuild-contents.sh" || { echo "❌ Contents-fixen misslyckades — avbryter innan bygget"; exit 1; }
grep -q 'CONTENTS_AREA' /usr/lib/live/build/lb_binary_debian-installer || { echo "❌ VERIFIERING MISSLYCKADES: patchen finns inte i live-build — avbryter"; exit 1; }
echo "✅ Contents-patch verifierad i live-build"

# --- Patch 2: DI-paketnamn (lilo/grub/linux-image-2.6 finns inte i trixie)
#     OCH grub-pc/grub-efi-amd64 Conflicts -> EFI-only: enbart grub-efi-amd64
echo "🔧 Patcher live-build installer-paket (trixie, EFI-only)..."
sudo bash "$BASE/fix-livebuild-di-packages.sh" || { echo "❌ DI-paket-fixen misslyckades — avbryter innan bygget"; exit 1; }
grep -q 'DI_REQ_PACKAGES="grub-efi-amd64"' /usr/lib/live/build/lb_binary_debian-installer || { echo "❌ VERIFIERING MISSLYCKADES: DI-paket-patchen finns inte — avbryter"; exit 1; }
echo "✅ DI-paket-patch verifierad i live-build (grub-efi-amd64 enbart)"

# --- Patch 3: data/debian-cd saknar trixie-katalog (netinst_udeb_include)
echo "🔧 Patcher live-build trixie-datapath..."
sudo bash "$BASE/fix-livebuild-trixie-data.sh" || { echo "❌ trixie-data-fixen misslyckades — avbryter innan bygget"; exit 1; }
[ -e /usr/share/live/build/data/debian-cd/trixie ] || { echo "❌ VERIFIERING MISSLYCKADES: trixie-datapath saknas — avbryter"; exit 1; }
echo "✅ trixie-datapath verifierad i live-build"

# --- Rensa gammal halvbyggd chroot och gamla markörer
echo "🧹 Rensar gammal chroot och markörer..."
rm -f "$BASE/.build-done" "$BASE/build-status.log"
sudo lb clean --purge 2>/dev/null || true

# --- Bygg i bakgrunden; skriv .build-done ENDAST om lb build lyckas
echo "📦 Startar bygget i bakgrunden (start: $(date '+%H:%M:%S'))..."
nohup env BASE="$BASE" bash -c '
  cd "$BASE" || exit 1
  sudo lb build 2>&1 | tee "$BASE/build.log"
  rc=${PIPESTATUS[0]}
  if [ "$rc" -eq 0 ] && ls "$BASE"/*.iso >/dev/null 2>&1; then
    touch "$BASE/.build-done"
    echo "BUILD_OK rc=$rc iso=$(ls "$BASE"/*.iso)" >> "$BASE/build-status.log"
  else
    echo "BUILD_FAILED rc=$rc $(date)" >> "$BASE/build-status.log"
  fi
' > /dev/null 2>&1 &
BUILD_PID=$!
echo "✅ Bygget körs nu (PID $BUILD_PID, logg: $BASE/build.log)"
echo "   Följ:            bash $BASE/watch-iso.sh"
echo "   KLART (med ISO): $BASE/.build-done + *.iso finns"
echo "   MISSLYCKAT:      se $BASE/build-status.log"
echo "   Nästa steg:      python3 $BASE/add-efi-boot.py"
