#!/bin/bash
# ============================================================
# LAPS MacBook Debian — ISO-byggare (Trixie, 4 skrivbord)
# Bygger live+installer-ISO med Cinnamon/XFCE/KDE/Sway + SDDM
# + Broadcom WiFi-firmware + svensk tangentbordslayout
# + MacBook8,1 SPI-fix (GRUB) + guide-repo + setup-meny
#
# .build-done skrivs ENDAST vid lyckad ISO (exit-kodskontroll).
# ============================================================
set -u
cd ~/laps-debian-live || exit 1

echo "🚀 LAPS Debian 4-DE — bygger Trixie-ISO"

# --- Patcha live-build bugg: security-deb måste heta -security, inte /updates
echo "🔧 Patcher live-build security-suite (trixie-security)..."
sudo sed -i 's|}/updates|}-security|g' /usr/lib/live/build/lb_chroot_archives || true

# --- Patcha live-build bugg 2: Contents-<arch>.gz ligger per komponent i trixie
echo "🔧 Patcher live-build Contents-URL (trixie per-komponent)..."
sudo bash ~/laps-debian-live/fix-livebuild-contents.sh || { echo "❌ Contents-fixen misslyckades — avbryter innan bygget"; exit 1; }
grep -q 'CONTENTS_AREA' /usr/lib/live/build/lb_binary_debian-installer || { echo "❌ VERIFIERING MISSLYCKADES: patchen finns inte i live-build — avbryter"; exit 1; }
echo "✅ Contents-patch verifierad i live-build"

# --- Patcha live-build bugg 3: DI-paketnamn (lilo/grub/linux-image-2.6) finns inte i trixie
#     OCH grub-pc/grub-efi-amd64 Conflicts -> EFI-only: enbart grub-efi-amd64
echo "🔧 Patcher live-build installer-paket (trixie, EFI-only)..."
sudo bash ~/laps-debian-live/fix-livebuild-di-packages.sh || { echo "❌ DI-paket-fixen misslyckades — avbryter innan bygget"; exit 1; }
grep -q 'DI_REQ_PACKAGES="grub-efi-amd64"' /usr/lib/live/build/lb_binary_debian-installer || { echo "❌ VERIFIERING MISSLYCKADES: DI-paket-patchen finns inte — avbryter"; exit 1; }
echo "✅ DI-paket-patch verifierad i live-build (grub-efi-amd64 enbart)"

# --- Patcha live-build bugg 4: data/debian-cd saknar trixie-katalog (netinst_udeb_include)
echo "🔧 Patcher live-build trixie-datapath..."
sudo bash ~/laps-debian-live/fix-livebuild-trixie-data.sh || { echo "❌ trixie-data-fixen misslyckades — avbryter innan bygget"; exit 1; }
[ -e /usr/share/live/build/data/debian-cd/trixie ] || { echo "❌ VERIFIERING MISSLYCKADES: trixie-datapath saknas — avbryter"; exit 1; }
echo "✅ trixie-datapath verifierad i live-build"

# --- Rensa gammal halvbyggd chroot och gamla markörer
echo "🧹 Rensar gammal chroot och markörer..."
rm -f ~/laps-debian-live/.build-done ~/laps-debian-live/build-status.log
sudo lb clean --purge 2>/dev/null || true

# --- Bygg i bakgrunden; skriv .build-done ENDAST om lb build lyckas
echo "📦 Startar bygget i bakgrunden (start: $(date '+%H:%M:%S'))..."
nohup bash -c '
  cd ~/laps-debian-live
  sudo lb build 2>&1 | tee ~/laps-debian-live/build.log
  rc=${PIPESTATUS[0]}
  if [ "$rc" -eq 0 ] && ls ~/laps-debian-live/*.iso >/dev/null 2>&1; then
    touch ~/laps-debian-live/.build-done
    echo "BUILD_OK rc=$rc iso=$(ls ~/laps-debian-live/*.iso)" >> ~/laps-debian-live/build-status.log
  else
    echo "BUILD_FAILED rc=$rc $(date)" >> ~/laps-debian-live/build-status.log
  fi
' > /dev/null 2>&1 &
BUILD_PID=$!
echo "✅ Bygget körs nu (PID $BUILD_PID, logg: ~/laps-debian-live/build.log)"
echo "   Se framsteg:  tail -20 ~/laps-debian-live/build.log"
echo "   KLAR (med ISO):  ~/laps-debian-live/.build-done + *.iso finns"
echo "   MISSLYCKAD:      se ~/laps-debian-live/build-status.log"