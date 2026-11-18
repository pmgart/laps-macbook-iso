#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# QEMU EFI-boot-test av den byggda ISO:n — skonsamt för värdmaskinen.
# EN instans, exakta PID:ar (aldrig pkill -f), begränsad livstid, låg belastning,
# serial+QMP för läsbar diagnos utan VNC.
#
# Användning: bash qemu-test-laps-iso.sh [iso-sökväg] [sekunder]
# Kräver: qemu-system-x86_64, ovmf, python3
set -u
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ISO="$(ls "$BASE"/*.iso 2>/dev/null | head -1)"
ISO="${1:-$DEFAULT_ISO}"
T="${2:-150}"                                   # max livstid i sekunder
W="${TMPDIR:-/tmp}/laps-qemu-test"
mkdir -p "$W"
LOG="$W/serial.log"
QMP_SOCK="$W/qmp.sock"
OVMF="$(ls /usr/share/ovmf/OVMF.fd /usr/share/OVMF/OVMF_CODE.fd 2>/dev/null | head -1)"

[ -n "$ISO" ] && [ -f "$ISO" ] || { echo "❌ Ingen ISO: ange sökväg eller bygg först"; exit 1; }
[ -n "$OVMF" ] || { echo "❌ OVMF saknas — apt install ovmf"; exit 1; }

# --- cleanup: bara vår egen PID-fil, aldrig pkill -f ---
cleanup() {
  if [ -f "$W/qemu.pid" ]; then
    QPID=$(cat "$W/qemu.pid")
    if kill -0 "$QPID" 2>/dev/null; then
      kill "$QPID" 2>/dev/null
      sleep 2
      kill -9 "$QPID" 2>/dev/null || true
    fi
    rm -f "$W/qemu.pid"
  fi
  echo "— QEMU-test slut —"
}
trap cleanup EXIT

echo "=== QEMU EFI-test: $ISO (max ${T}s, skonsam) ==="

# En skrivbar kopia av OVMF (QEMU skriver NVRAM till firmware-filen)
cp "$OVMF" "$W/efivars.fd"

rm -f "$LOG" "$QMP_SOCK"

# EN process: nice-läge, 2 GB RAM (ISO:n behöver ~1,5 GB), ingen CPU-slösning
nice -n 19 qemu-system-x86_64 \
  -m 2048 \
  -enable-kvm \
  -bios "$W/efivars.fd" \
  -cdrom "$ISO" \
  -boot d \
  -display none \
  -serial "file:$LOG" \
  -net none \
  -qmp "unix:$QMP_SOCK,server,nowait" &
QPID=$!
echo "$QPID" > "$W/qemu.pid"
echo "QEMU PID: $QPID"

# Vänta på QMP-socket
for _ in $(seq 1 30); do [ -S "$QMP_SOCK" ] && break; sleep 1; done

# Bevaka CD-läsning via QMP: GRUB-menyn går till gfxterm och kerneln har quiet
# splash, så serial förblir tyst. Läs-kolumnen är beviset:
#   <10 MB = GRUB död/ingen boot; >100 MB = kernel+initrd laddade; >1,5 GB = squashfs läses
read_rd() {
  python3 - "$QMP_SOCK" <<'PYEOF' 2>/dev/null
import json, socket, sys
try:
    s = socket.socket(socket.AF_UNIX); s.settimeout(3)
    s.connect(sys.argv[1]); f = s.makefile("rw"); f.readline()
    def cmd(c):
        f.write(json.dumps(c) + "\n"); f.flush()
        return json.loads(f.readline())
    cmd({"execute": "qmp_capabilities"})
    for b in cmd({"execute": "query-blockstats"})["return"]:
        if b.get("device") == "ide1-cd0":
            print(b.get("stats", {}).get("rd_bytes", 0)); break
except Exception:
    print(-1)
PYEOF
}

DEADLINE=$((SECONDS + T))
LAST_RD=0
while [ $SECONDS -lt $DEADLINE ]; do
  if ! kill -0 "$QPID" 2>/dev/null; then echo "QEMU avslutades"; break; fi
  RD=$(read_rd)
  if [ "$RD" != "-1" ] && [ "$RD" != "$LAST_RD" ]; then
    echo "[$(date +%H:%M:%S)] CD läst: $((RD/1024/1024)) MB"
    LAST_RD=$RD
  fi
  if [ "$RD" -gt 100000000 ] 2>/dev/null; then
    echo "✅ KERNEL+INITRD LÄSTA (>100 MB CD-läsning) — boot-kedjan fungerar!"
    # Låt live-boot montera squashfs (~1,5 GB läsning) som slutbevis:
    sleep 20
    RD2=$(read_rd)
    echo "[$(date +%H:%M:%S)] CD läst efter 20s till: $((RD2/1024/1024)) MB"
    if [ "$RD2" -gt 1500000000 ] 2>/dev/null; then
      echo "✅✅ LIVE-BOOT LÄSER SQUASHFS (>1,5 GB) — systemet startar!"
    fi
    break
  fi
  sleep 5
done

echo "=== SERIAL-LOGG (sista 25 rader, kontrolltecken rensade) ==="
strings "$LOG" 2>/dev/null | tail -25
echo "=== SLUT ==="
