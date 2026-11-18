#!/bin/bash
# Fortsätter ett avbrucket live-build från binärstadiet (sparar ~35 min
# eftersom bootstrap+chroot redan är klara). Kräver sudo (lösenord en gång).
#
# Paus-immun: hela bygget körs i en nohup-avknoppad bakgrundsprocess som
# INTE följer terminalens Ctrl+Z/Ctrl+C. Statuslogik med absoluta sökvägar
# (sudo gör $HOME=/root — använd aldrig ~ här).
set -u
BASE=/home/pablo-magana/laps-debian-live
cd "$BASE" || exit 1

echo "🔧 Verifierar patchar..."
grep -q 'CONTENTS_AREA' /usr/lib/live/build/lb_binary_debian-installer || { echo "❌ Kör först: sudo bash $BASE/fix-livebuild-contents.sh"; exit 1; }
grep -q 'DI_REQ_PACKAGES="grub-efi-amd64"' /usr/lib/live/build/lb_binary_debian-installer || { echo "❌ Kör först: sudo bash $BASE/fix-livebuild-di-packages.sh"; exit 1; }
echo "✅ Contents- + DI-paket-patchar aktiva"

# Städa gamla lås och ev. frusna processer från tidigare försök
sudo rm -f "$BASE/.lock" /var/cache/apt/archives/lock "$BASE/chroot/var/lib/dpkg/lock-frontend" "$BASE/chroot/var/lib/dpkg/lock" 2>/dev/null

rm -f "$BASE/.build-done"
echo "📦 Startar lb binary i paus-immun bakgrund (start: $(date '+%H:%M:%S'))..."
nohup bash -c '
  cd /home/pablo-magana/laps-debian-live
  sudo lb binary 2>&1 | tee -a /home/pablo-magana/laps-debian-live/build.log
  rc=${PIPESTATUS[0]}
  if [ "$rc" -eq 0 ] && ls /home/pablo-magana/laps-debian-live/*.iso >/dev/null 2>&1; then
    touch /home/pablo-magana/laps-debian-live/.build-done
    echo "BUILD_OK(binary) rc=$rc iso=$(ls /home/pablo-magana/laps-debian-live/*.iso)" >> /home/pablo-magana/laps-debian-live/build-status.log
  else
    echo "BUILD_FAILED(binary) rc=$rc $(date)" >> /home/pablo-magana/laps-debian-live/build-status.log
  fi
' > /dev/null 2>&1 &
disown
echo "✅ Bygget körs nu oberoende av terminalen (pausa inte med Ctrl+Z — det påverkar inte längre bygget)"
echo "   Framsteg: tail -f $BASE/build.log   (Avsluta med Ctrl+C)"
echo "   Klart:    $BASE/.build-done + *.iso finns — säg 'status' till agenten så verifieras ISO:n"