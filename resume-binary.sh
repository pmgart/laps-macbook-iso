#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Fortsätter ett avbrutet live-build från binärstadiet (sparar ~35 min
# eftersom bootstrap+chroot redan är klara). Kräver sudo (lösenord en gång).
#
# Paus-immun: hela bygget körs i en nohup-avknoppad bakgrundsprocess som
# INTE följer terminalens Ctrl+Z/Ctrl+C. Absoluta sökvägar överallt
# (sudo gör $HOME=/root — använd aldrig ~ i skript som körs via sudo).
set -u
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$BASE" || exit 1

echo "🔧 Verifierar patchar..."
grep -q 'CONTENTS_AREA' /usr/lib/live/build/lb_binary_debian-installer || { echo "❌ Kör först: sudo bash $BASE/fix-livebuild-contents.sh"; exit 1; }
grep -q 'DI_REQ_PACKAGES="grub-efi-amd64"' /usr/lib/live/build/lb_binary_debian-installer || { echo "❌ Kör först: sudo bash $BASE/fix-livebuild-di-packages.sh"; exit 1; }
echo "✅ Contents- + DI-paket-patchar aktiva"

# Städa gamla lås och ev. frusna processer från tidigare försök
sudo rm -f "$BASE/.lock" /var/cache/apt/archives/lock \
           "$BASE/chroot/var/lib/dpkg/lock-frontend" "$BASE/chroot/var/lib/dpkg/lock" 2>/dev/null

rm -f "$BASE/.build-done"
echo "📦 Startar lb binary i paus-immun bakgrund (start: $(date '+%H:%M:%S'))..."
nohup env BASE="$BASE" bash -c '
  cd "$BASE" || exit 1
  sudo lb binary 2>&1 | tee -a "$BASE/build.log"
  rc=${PIPESTATUS[0]}
  if [ "$rc" -eq 0 ] && ls "$BASE"/*.iso >/dev/null 2>&1; then
    touch "$BASE/.build-done"
    echo "BUILD_OK(binary) rc=$rc iso=$(ls "$BASE"/*.iso)" >> "$BASE/build-status.log"
  else
    echo "BUILD_FAILED(binary) rc=$rc $(date)" >> "$BASE/build-status.log"
  fi
' > /dev/null 2>&1 &
disown
echo "✅ Bygget körs nu oberoende av terminalen (pausa inte med Ctrl+Z — det påverkar inte längre bygget)"
echo "   Framsteg: tail -f $BASE/build.log   (Avsluta med Ctrl+C)"
echo "   Klart:    $BASE/.build-done + *.iso finns"
echo "   Nästa steg: python3 $BASE/add-efi-boot.py"
