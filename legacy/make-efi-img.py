#!/usr/bin/env python3
"""Skapar FAT EFI-image sudo-fritt: PyFat.mkfs + PyFatFS för filer."""
import sys
from pathlib import Path

efi_img = sys.argv[1]
bootx64 = sys.argv[2]
grub_cfg = sys.argv[3]
size_bytes = int(sys.argv[4]) if len(sys.argv) > 4 else 33 * 1024 * 1024

# 1. Skapa tom fil
Path(efi_img).parent.mkdir(parents=True, exist_ok=True)
with open(efi_img, "wb") as f:
    f.truncate(size_bytes)

from pyfatfs.PyFat import PyFat
from pyfatfs.PyFatFS import PyFatFS

fat = PyFat()
fat.mkfs(efi_img, fat_type=PyFat.FAT_TYPE_FAT32, size=size_bytes, label="EFIBOOT")
fat.close()

fs = PyFatFS(efi_img)
fs.makedir("/efi", recreate=True)
fs.makedir("/efi/boot", recreate=True)
with fs.openbin("/efi/boot/bootx64.efi", "wb") as f:
    f.write(Path(bootx64).read_bytes())
with fs.openbin("/efi/boot/grub.cfg", "wb") as f:
    f.write(Path(grub_cfg).read_bytes())
fs.close()
print("FAT EFI-image skriven OK:", efi_img, size_bytes, "bytes")