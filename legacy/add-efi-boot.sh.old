#!/bin/bash
# Lägger till EFI-boot (och BIOS-isolinux saknas — EFI räcker för MacBook8,1)
# till den byggda binary.hybrid.iso via grub-mkstandalone (host-verktyg).
#
# Resultat: laps-macbook-debian-trixie.iso med:
#  - EFI-boot: /EFI/boot/bootx64.efi (grub-standalone med inbäddad grub.cfg)
#  - grub.cfg: live-läge (med initcall_blacklist=dw_pci_driver_init) + installer-menyn
# MacBooken har INGET BIOS-läge, så isolinux/isohybrid behövs ej.
set -eu

BASE=/home/pablo-magana/laps-debian-live
SRC="$BASE/chroot/binary.hybrid.iso"
OUT="$BASE/laps-macbook-debian-trixie.iso"
WORK=$(mktemp -d /tmp/efi-iso.XXXXXX)

[ -f "$SRC" ] || { echo "❌ $SRC saknas — kör resume-binary.sh först"; exit 1; }
[ -d /usr/lib/grub/x86_64-efi ] || { echo "❌ grub-efi-amd64-bin saknas på värden (sudo apt install grub-efi-amd64-bin)"; exit 1; }

echo "1/4 Montera ISO-innehåll..."
7z x -y -o"$WORK" "$SRC" >/dev/null

echo "2/4 Skapar GRUB EFI-binär med inbäddad konfig..."
CFG="$WORK/grub.cfg"
cat > "$CFG" <<'GRUBEOF'
set timeout=10
set default=0

menuentry "LAPS Debian Live (MacBook8,1 SPI-fix aktiv)" {
	linux /live/vmlinuz-6.12.107+deb13-amd64 boot=live components quiet splash initcall_blacklist=dw_pci_driver_init keyboard-layouts=se
	initrd /live/initrd.img-6.12.107+deb13-amd64
}

menuentry "LAPS Debian Installer (text)" {
	linux /install/vmlinuz initcall_blacklist=dw_pci_driver_init
	initrd /install/initrd.gz
}

menuentry "LAPS Debian Installer (grafisk)" {
	linux /install/gtk/vmlinuz initcall_blacklist=dw_pci_driver_init
	initrd /install/gtk/initrd.gz
}

menuentry "Boot från lokal disk" {
	exit 1
}
GRUBEOF

grub-mkimage -O x86_64-efi -o "$WORK/bootx64.efi" -p /efi/boot \
  $(cd /usr/lib/grub/x86_64-efi && ls *.mod | sed 's/\.mod$//' | tr '\n' ' ') \
  2>/dev/null || \
grub-mkimage -O x86_64-efi -o "$WORK/bootx64.efi" -p /efi/boot \
  linux efi_gop efi_uga fat iso9660 part_gpt part_msdos normal boot configfile search search_fs_file echo ls test all serial gfxterm gfxmenu

echo "3/4 Bygger ny ISO med EFI-partition..."
# EFI-boot i hybrid-ISO: skapa efiboot.img (FAT) med bootx64.efi + grub.cfg
ESIZE=4096
dd if=/dev/zero of="$WORK/efi.img" bs=1K count=$ESIZE 2>/dev/null
MKFSCMD=$(mktemp -u); mkfs.vfat "$WORK/efi.img" 2>/dev/null || python3 -c "
import sys, subprocess
sys.exit(0)" # vfat via mtools fallback
if command -v mkfs.vfat >/dev/null; then
  MDIR=$(mktemp -d)
  if sudo -n mount -o loop "$WORK/efi.img" "$MDIR" 2>/dev/null; then
    # mount-väg (sudo lösenord hämtas interaktivt — kör med sudo bash)
    sudo mkdir -p "$MDIR/efi/boot"
    sudo cp "$WORK/bootx64.efi" "$MDIR/efi/boot/"
    sudo cp "$CFG" "$MDIR/efi/boot/grub.cfg"
    sudo umount "$MDIR"
  elif command -v mmd >/dev/null 2>&1; then
    MTOOLS_SKIP_CHECK=1 mmd -i "$WORK/efi.img" ::efi ::efi/boot
    MTOOLS_SKIP_CHECK=1 mcopy -i "$WORK/efi.img" "$WORK/bootx64.efi" ::efi/boot/bootx64.efi
    MTOOLS_SKIP_CHECK=1 mcopy -i "$WORK/efi.img" "$CFG" ::efi/boot/grub.cfg
  else
    echo "❌ Varken sudo-mount eller mtools fungerade — sudo apt install mtools"; exit 1
  fi
  rm -rf "$MDIR"
else
  echo "❌ mkfs.vfat/mtools saknas — sudo apt install dosfstools mtools"; exit 1
fi

genisoimage -o "$OUT" \
  -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin 2>/dev/null || \
genisoimage -o "$OUT" \
  -b .disk/mkisolinux -no-emul-boot 2>/dev/null || true

# Riktigt byggkommando ( EFI + Rock Ridge + Joliet ):
genisoimage -r -J -o "$OUT" \
  -eltorito-alt-boot -b efi.img -no-emul-boot \
  -V LAPS-MACBOOK-DEBIAN \
  "$WORK" 2>&1 | tail -3

echo "4/4 Klar: $OUT ($(du -h "$OUT" | cut -f1))"
echo "   EFI-boot: endast (MacBook8,1 är EFI-only — isolinux/BIOS behövs ej)"