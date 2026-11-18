#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# LAPS Debian ISO — watchdog. Pollar bygget och rapporterar när det är klart.
set -u
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="$BASE/build.log"

echo "🛰️  Watchdog startad $(date '+%H:%M:%S') — övervakar bygget i $BASE..."

# Vänta tills inga byggprocesser (lb build / debootstrap / apt-get i chrooten) finns kvar
while true; do
    # shellcheck disable=SC2009  # medvetet ps|grep: vi letar efter externa lb-processer
    RUNNING=$(ps aux | grep -E 'lb (build|clean)|debootstrap|apt-get --yes --force-yes upgrade|unsquashfs|mksquashfs|xorriso' | grep -v grep | wc -l)
    if [ "$RUNNING" -eq 0 ]; then
        # Dubbelkolla: ingen chroot-mount aktiv?
        sleep 5
        # shellcheck disable=SC2009
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

# Hitta ISO (både live-build-standardnamn och LAPS-namnet)
ISO=$(ls -t "$BASE"/live-image-*.iso "$BASE"/laps-*.iso 2>/dev/null | head -1)
if [ -n "$ISO" ]; then
    echo "✅ ISO SKAPAD: $ISO ($(du -h "$ISO" | cut -f1))"
elif [ -f "$BASE/build-status.log" ]; then
    echo "❌ INGEN ISO hittades — status: $(tail -1 "$BASE/build-status.log")"
else
    echo "❌ INGEN ISO hittades — bygget verkar ha misslyckats."
fi

echo ""
echo "--- Sista 12 raderna i build.log ---"
tail -12 "$LOG" 2>/dev/null || echo "(ingen logg)"
echo ""
echo "--- EFI-steg kvar? ---"
if ls "$BASE"/*.iso >/dev/null 2>&1; then
    echo "Kör nu: python3 $BASE/add-efi-boot.py && bash $BASE/verify-iso.sh"
fi
