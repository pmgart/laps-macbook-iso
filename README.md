# laps-macbook-iso — byggsystemet för LAPS Debian-ISO (MacBook8,1)

Detta repo är **byggsystemet** som producerar den anpassade Debian 13 (trixie) live/installer-ISO:n
för 12-tums Retina MacBook (A1534 / MacBook8,1). Enhetsfixarna (ljud, webbkamera, sleep) ligger i
det separata repot [`pmgart/macbook8-1-debian-guide`](https://github.com/pmgart/macbook8-1-debian-guide)
och bakas in i imagen under `/opt/macbook8-1-debian-guide`.

## Vad som finns här

```
config/                  live-build-konfiguration (det som gör ISO:n till *din* ISO)
  package-lists/         desktops.list.chroot — Cinnamon + XFCE + KDE + Sway + SDDM + firmware
  binary                 LB_BOOTLOADER=grub-efi, boot-parametrar, volymetikett
  bootstrap              trixie, amd64, speglar, arkivarea
  chroot                 squashfs, systemd, kernel flavour
  hooks/                 9990-fix-keyboard (SPI-GRUB + svensk layout + §/<>-fix), 9991-display-manager
  binary_debian-installer/preseed.cfg
  includes.chroot/opt/macbook8-1-debian-guide/   fryst kopia av guide-repot (commit 86e996c, utan .git)
  includes.chroot/usr/local/bin/laps-macbook-setup
build-laps-debian.sh     huvudbygge: patchar live-build, lb clean --purge, lb build i bakgrund
resume-binary.sh         återupptar från binärstadiet (sparar ~35 min)
fix-livebuild-*.sh       tre patchar mot /usr/lib/live/build (se Fällor)
add-efi-boot.py          lägger EFI-boot i ISO:n efter lb binary (grub-mkstandalone + mtools + xorriso)
make-efi-img.py          ÄLDRE pyfatfs-variant, ger korrupt FAT — referens endast, används inte
verify-iso.sh            verifierar GRUB-parametrar, squashfs, guide-repo, setup-meny
qemu-test-laps-iso.sh    QEMU-boot-test
watch-iso.sh             byggprogress
sudoers-laps-livebuild   exempel på NOPASSWD-regel för byggskriptet (ej verifierad installerad)
manifests/               paketlistor från den verifierade byggkörningen + ISO-mått (se MANIFEST.md)
tools/isohdpfx.bin       432-byte MBR-blob som add-efi-boot.py kräver (se Fällor)
tools/setup-host-deps.sh kontrollerar värdberoenden och lägger blobben på rätt plats
local/                   tomma live-build-overrides (scripts/, functions/)
```

Det som **inte** finns här: ISO-filen, `chroot/`, `cache/`. De är byggresultat — se `MANIFEST.md`
för artefaktens checksumma och förvara ISO:n separat (rekommenderat: `/mnt/Media/Backup`).

## Bygga

Skripten har hårdkodad arbetskatalog. Klona dit de förväntar sig:

```bash
git clone git@github.com:pmgart/laps-macbook-iso.git ~/laps-debian-live
cd ~/laps-debian-live

bash tools/setup-host-deps.sh      # kontrollera live-build, xorriso, mtools, MBR-blob
```

Sedan, i denna ordning:

```bash
# 1. Patcha live-build (kräver sudo; verifierar sig själva med grep)
sudo bash fix-livebuild-contents.sh
sudo bash fix-livebuild-di-packages.sh
sudo bash fix-livebuild-trixie-data.sh

# 2. Fullt bygge (~40 min), eller resume-binary.sh om chroot redan finns
./build-laps-debian.sh

# 3. EFI-boot läggs på EFTER lb binary (live-build 3.0~a57 kan inte grub-efi för ISO)
python3 add-efi-boot.py

# 4. Verifiera innan flashning
bash verify-iso.sh
```

## Fällor (alla har kostat tid minst en gång)

1. **live-build-versionen är låst i praktiken.** Patcharna är `sed` mot `/usr/lib/live/build/*` i
   `3.0~a57-1ubuntu54`. Uppgraderas paketet kan alla tre sluta träffa — skripten grep-verifierar och
   avbryter, men kontrollera versionen först.
2. **`LB_BOOTLOADER=grub-efi` fungerar inte i denna live-build för ISO.** `lb binary` ger ett
   `binary.hybrid.iso` utan bootloader. Därför `add-efi-boot.py` som separat steg.
3. **MBR-blobben `isohdpfx-laps.bin` (432 byte) låg bara i `~/.hermes/cache/scratch/`, som städas.**
   Den är nu återställd till `tools/isohdpfx.bin` (sha256 `7ec30d04…a143`) och kopieras på plats av
   `tools/setup-host-deps.sh`. `add-efi-boot.py` vägrar köra om den saknas.
4. **Kärnversionen är hårdkodad i GRUB-menyn** (`6.12.107+deb13-amd64` i `add-efi-boot.py`). Ett
   nybygge med nyare trixie-kärna ger andra filnamn i `/live/` → menyposterna måste uppdateras.
5. **`sudo bash` tappar `~`** (`$HOME=/root`). Skript som körs via sudo använder absoluta sökvägar.
6. **Överbliven `.lock` blockerar `lb binary`** (”live-build locked”) efter dödade processer.
   `resume-binary.sh` städar den.
7. **Pausa aldrig bygget med Ctrl+Z** — frusna processer håller apt-lås. Skripten kör i `nohup`-bakgrund.
8. **`config/archives` är tom** → ingen snapshot-pinning. En rebuild idag hämtar dagens trixie-paket
   och ger ett *annat* ISO. Vill du kunna återskapa exakt: pinna `snapshot.debian.org` där.

## Reproducerbarhet — ärligt läge

Repot kan återskapa en **fungerande** ISO av samma typ, men inte garanterat ett **identiskt** ISO:
osnapshotad trixie-spegel, live-build-version och kärnversion påverkar resultatet. Den enda verifierade
binären är artefakten i `MANIFEST.md` — arkivera den, den går inte att räkna hem igen.
