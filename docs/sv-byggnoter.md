> **Observera:** detta är de ursprungliga svenska byggnoterna från 2026-09-25, flyttade hit
> oförändrade. Den aktuella, engelska bygginstruktionen finns i [`../README.md`](../README.md).

# LAPS Debian Live — MacBook8,1 ISO

Custom Debian 13 (trixie) live/installer-ISO för 12-tums Retina MacBook (A1534 / MacBook8,1).

## Innehåll

| Komponent | Hur | Status |
|---|---|---|
| Cinnamon + svensk layout | package-lists + xorg.conf hook | ✅ |
| Broadcom Wi-Fi firmware | firmware-brcm80211 i paketlistan | ✅ |
| SPI-tangentbord/styrplatta (PIO) | `initcall_blacklist=dw_pci_driver_init` i LB_BOOTAPPEND_LIVE **och** LB_BOOTAPPEND_INSTALL | ✅ |
| Guide-repo med alla fixes | `config/includes.chroot/opt/macbook8-1-debian-guide` (klon av github.com/pmgart/macbook8-1-debian-guide) | ✅ |
| Setup-meny för installerat system | `/usr/local/bin/laps-macbook-setup` (använder repots gated-skript) | ✅ |
| Svensk §/<>-tangentbordsfix | hook `9990-fix-keyboard.hook.chroot` → Xsession.d | ✅ |
| Ljud/webcam/sleep | installeras **efter** installation via `laps-macbook-setup` (repots egna skript, kräver körning på riktig maskin) | via meny |

## Bygg

```bash
~/laps-debian-live/build-laps-debian.sh   # bygger i bakgrund, klar när .build-done finns
```

## Användning (reinstall-flöde)

1. Flasha ISO:n till USB (USB-C-adapter behövs på MacBook8,1).
2. Boota live-läget → tangentbord/styrplatta fungerar direkt (PIO-parametern är i GRUB).
3. Installera Debian via calamares/debian-installer (installationskärnan har samma GRUB-parameter).
4. Efter omstart i installerat system: kör `sudo laps-macbook-setup` → välj ljud, sleep, webbkamera.
   Allt är gated, med restore-skript, enligt repots AGENTS.md-regler.
5. Guide och diagnostik ligger i `/opt/macbook8-1-debian-guide`.

## Kända begränsningar

- Ljudpatchen byggs vid installation (kräver nätverk + linux-headers) — samma väg som repot verifierat.
- Webcam-firmware extraheras vid installation (kräver nätverk).
- Suspend-then-hibernate kräver swap-partition — välj swap vid installationen.
- Tangentbordsbelysning och automatisk audio-rebuild vid kerneluppdatering är ej lösta (se repot).

## Verifiering före användning

- [ ] QEMU-boot: live-läget startar, `cat /proc/cmdline` innehåller initcall_blacklist
- [ ] ISO-innehåll: /opt/macbook8-1-debian-guide och /usr/local/bin/laps-macbook-setup finns i squashfs
- [ ] Riktig maskin: boot från USB, tangentbord fungerar i live-läget
- [ ] Riktig maskin: full installation på extern disk + `laps-macbook-setup` steg för steg