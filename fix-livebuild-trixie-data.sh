#!/bin/bash
# Fixar live-build: /usr/share/live/build/data/debian-cd saknar trixie-katalog
# (finns bara sid/ äldre). Symlinkar sid->trixie så netinst_udeb_include hittas.
set -e
D=/usr/share/live/build/data/debian-cd
if [ -e "$D/trixie" ]; then echo "✅ trixie-datapath finns redan"; exit 0; fi
[ -d "$D/sid" ] || { echo "❌ $D/sid saknas"; exit 1; }
ln -s sid "$D/trixie"
echo "✅ Symlink $D/trixie -> sid skapad"
