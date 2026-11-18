#!/bin/bash
# LAPS Debian ISO — watchdog. Pollar bygget och rapporterar när det är klart.
set -u
LOG=~/laps-debian-live/build.log
PROJ=~/laps-debian-live

echo "🛰️  Watchdog startad $(date '+%H:%M:%S') — övervakar bygget..."

# Vänta tills inga byggprocesser (lb build / debootstrap / apt-get i chrooten) finns kvar
while true; do
    RUNNING=$(ps aux | grep -E 'lb (build|clean)|debootstrap|apt-get --yes --force-yes upgrade|unsquashfs|mksquashfs|xorriso' | grep -v grep | wc -l)
    if [ "$RUNNING" -eq 0 ]; then
        # Dubbelkolla: ingen chroot-mount aktiv?
        sleep 5
        RUNNING2=$(ps aux | grep -E 'lb (build|clean)|debootstrap|apt-get --yes --force-yes upgrade' | grep -v grep | wc -l)
        if [ "$RUNNING2" -eq 0 ]; then
            break
        fi
    fi
    sleep 20
done

echo ""
echo "══════════════════════════════════════════════"
echo "🏁 Bygget avslutat $(date '+%H:%M:%S')"
echo "══════════════════════════════════════════════"

# Hitta ISO
ISO=$(ls -t "$PROJ"/live-image-*.iso 2>/dev/null | head -1)
DL=$(ls -t ~/Downloads/live-image-*.iso 2>/dev/null | head -1)
if [ -n "$ISO" ]; then
    SIZE=$(du -h "$ISO" | cut -f1)
    echo "✅ ISO SKAPAD: $ISO ($SIZE)"
elif [ -n "$DL" ]; then
    SIZE=$(du -h "$DL" | cut -f1)
    echo "✅ ISO I DOWNLOADS: $DL ($SIZE)"
else
    echo "❌ INGEN ISO hittades — bygget verkar ha misslyckats."
fi

echo ""
echo "--- Sista 12 raderna i build.log ---"
tail -12 "$LOG" 2>/dev/null || echo "(ingen logg)"
echo ""
echo "--- Finns live-mapp med squashfs? ---"
ls -lh "$PROJ"/live/ 2>/dev/null | head -5 || echo "(ingen live-mapp)"
