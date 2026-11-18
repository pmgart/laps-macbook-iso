# MANIFEST — LAPS Debian MacBook8,1 ISO

Artefaktregister. Uppdateras varje gång en ny ISO verifieras.

## Artefakt som denna repo-version hör till

| Fält | Värde |
|---|---|
| Fil | `laps-macbook-debian-trixie.iso` |
| Byte | 3 033 710 592 (2,83 GiB) |
| SHA256 | `1351d6c95e7a0bd869cb2062662d8c4b59a20b954f55bbd88e2213428ead44e6` |
| Byggdatum | 2026-09-25 16:59 (ISO-mtime) |
| Volymetikett | `LAPS-DEBIAN-CINNAMON` (LB_ISO_VOLUME), applikation `LAPS Debian Cinnamon` |
| Skrivbord | Cinnamon + XFCE + KDE Plasma + Sway, SDDM som enda DM |
| Kärna i imagen | `6.12.107+deb13-amd64` |
| Paket (binary) | 2 840 st (`manifests/binary.packages.txt`) |
| Paket (chroot live) | 2 840 st (`manifests/chroot.packages.live.txt`) |
| ISO-innehåll | 515 filer / 335 kataloger |
| `live/filesystem.squashfs` | 2 621 513 728 byte |
| `boot/grub/efi.img` | 8 388 608 byte (FAT, mtools-byggd) |
| `EFI/boot/bootx64.efi` | 897 024 byte (grub-mkstandalone) |
| `boot/grub/grub.cfg` | 1 071 byte (5 menyposter, SPI-fix i alla) |

## Arkiverad kopia

| Plats | Innehåll | Status |
|---|---|---|
| `/mnt/Media/Backup/macbook-iso/laps-macbook-debian-trixie.iso` | ISO | sha256 kontrollerad 2026-11-18, OK |
| `/mnt/Media/Backup/macbook-iso/laps-macbook-debian-trixie.iso.sha256` | checksumma | — |
| `github.com/pmgart/laps-macbook-iso` (privat) | detta byggsystem | commit `d989b9a` |

## Byggvärd

| Komponent | Version |
|---|---|
| live-build | `3.0~a57-1ubuntu54` (Ubuntu-paketerad build — patcharna är knutna till denna) |
| Distribution | trixie (Debian 13) |
| EFI-verktyg | `grub-mkstandalone`, `mtools` (mformat/mmd/mcopy), `xorriso`, `7z` |
| MBR-blob | `tools/isohdpfx.bin`, 432 byte, sha256 `7ec30d044a4bc52f35ac53c24aa75b56a8e7f892a8129c098e48467da069a143` |

`pyfatfs` krävs **inte** av den fungerande EFI-vägen (den använder mtools).
`make-efi-img.py` är äldre kod som använde pyfatfs och gav korrupt FAT — sparat som referens, används inte.

## Verifieringsstatus

- [x] `verify-iso.sh`: GRUB-parametrar, squashfs, guide-repo, setup-meny (per 2026-09-25)
- [x] QEMU-boot: live-läget startar, `initcall_blacklist` i `/proc/cmdline`
- [ ] Riktig MacBook8,1: boot från USB — **ej utfört**
- [ ] Riktig MacBook8,1: full installation + `laps-macbook-setup` — **ej utfört**

## Ändringshistorik för artefakten

| Datum | Händelse |
|---|---|
| 2026-09-24 | Första EFI-ISO, 1,93 GB, sha256 `ef2d5004…9c1c6` (Cinnamon-only, `all-desktops`-varianten krävde full rebuild) |
| 2026-09-25 | Full rebuild med 4 skrivbord → nuvarande artefakt (tabellen ovan) |
