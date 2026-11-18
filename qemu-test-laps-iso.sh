#!/bin/bash
# QEMU EFI-boot-test av LAPS MacBook ISO — skonsamt för arbetsstationen.
# Regler från 2026-09-24-incidenten: EN instans, exakta PID:ar (aldrig pkill -f),
# begränsad livstid, låg belastning, serial+QMP för läsbar diagnos utan VNC.
# Användning: bash qemu-test-laps-iso.sh <iso-sökväg> [sekunder]

ISO="${1:-/home/pablo-magana/laps-debian-live/laps-macbook-debian-trixie.iso}"
T="${2:-150}"                       # max livstid i sekunder
W=/home/pablo-magana/.hermes/cache/scratch/qemu-gold
mkdir -p "$W"
LOG="$W/serial.log"
QMP_SOCK="$W/qmp.sock"

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
cp /usr/share/ovmf/OVMF.fd "$W/efivars.fd"

rm -f "$LOG" "$QMP_SOCK"

# EN process: nice-läge, 2GB RAM (ISO:n behöver ~1.5G), ingen CPU-slösning
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
for i in $(seq 1 30); do [ -S "$QMP_SOCK" ] && break; sleep 1; done

# Bevaka: (1) kernel-boot via CD-läsning (blockstats) — GRUB-meny går till gfxterm,
#         kerneln har quiet splash → serial förblir tyst; läs-kolumnen är beviset:
#         <10MB = GRUB död/ingen boot; >100MB = kernel+initrd laddade; >1GB = live-boot läser squashfs
DEADLINE=$((SECONDS + T))
LAST_RD=0
while [ $SECONDS -lt $DEADLINE ]; do
  if ! kill -0 "$QPID" 2>/dev/null; then echo "QEMU avslutades"; break; fi
  RD=$(python3 - "$QMP_SOCK" <<'PYEOF' 2>/dev/null
import socket, json, sys
try:
    s = socket.socket(socket.AF_UNIX); s.settimeout(3)
    s.connect(sys.argv[1]); f = s.makefile("rw"); f.readline()
    def cmd(c):
        f.write(json.dumps(c)+"\n"); f.flush()
        return json.loads(f.readline())
    cmd({"execute":"qmp_capabilities"})
    st = cmd({"execute":"query-blockstats"})["return"]
    for b in st:
        if b.get("device") == "ide1-cd0":
            print(b.get("stats",{}).get("rd_bytes",0)); break
except Exception:
    print(-1)
PYEOF
)
  if [ "$RD" != "-1" ] && [ "$RD" != "$LAST_RD" ]; then
    echo "[$(date +%H:%M:%S)] CD läst: $((RD/1024/1024)) MB"
    LAST_RD=$RD
  fi
  if [ "$RD" -gt 100000000 ] 2>/dev/null; then
    echo "✅ KERNEL+INITRD LÄSTA (>100MB CD-läsning) — boot-kedjan fungerar!"
    # Låt live-boot montera squashfs (~1.5GB läsning) som slutbevis:
    sleep 20
    RD2=$(python3 - "$QMP_SOCK" <<'PYEOF' 2>/dev/null
import socket, json, sys
try:
    s = socket.socket(socket.AF_UNIX); s.settimeout(3)
    s.connect(sys.argv[1]); f = s.makefile("rw"); f.readline()
    def cmd(c):
        f.write(json.dumps(c)+"\n"); f.flush()
        return json.loads(f.readline())
    cmd({"execute":"qmp_capabilities"})
    st = cmd({"execute":"query-blockstats"})["return"]
    for b in st:
        if b.get("device") == "ide1-cd0":
            print(b.get("stats",{}).get("rd_bytes",0)); break
except Exception:
    print(-1)
PYEOF
)
    echo "[$(date +%H:%M:%S)] CD läst efter 20s till: $((RD2/1024/1024)) MB"
    if [ "$RD2" -gt 1500000000 ] 2>/dev/null; then
      echo "✅✅ LIVE-BOOT LÄSER SQUASHFS (>1.5GB) — systemet startar!"
    fi
    break
  fi
  sleep 5
done

echo "=== SERIAL-LOGG (sista 25 rader, kontrolltecken rensade) ==="
strings "$LOG" 2>/dev/null | tail -25
echo "=== SLUT ==="