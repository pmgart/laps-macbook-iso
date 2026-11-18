#!/bin/bash
# Fixar live-build lb_binary_debian-installer: Debian trixie har flyttat
# Contents-<arch>.gz till per-komponent-undermappar (dists/trixie/main/...).
# Gamla platta URL:en ger 404 -> bygget fallerar i lb_binary_debian-installer.
# Denna fix hämtar Contents från varje arkivkomponent (idempotent).
set -e

SCRIPT=/usr/lib/live/build/lb_binary_debian-installer
[ -f "$SCRIPT" ] || { echo "❌ $SCRIPT hittas inte"; exit 1; }

if grep -q '_CONTENTS_AREA' "$SCRIPT"; then
  echo "✅ Redan patchad (Contents per komponent) — inget att göra."
  exit 0
fi

cp -a "$SCRIPT" "${SCRIPT}.bak.$(date +%Y%m%d-%H%M%S)"
python3 - "$SCRIPT" <<'PY'
import sys
path = sys.argv[1]
with open(path) as f:
    src = f.read()

old = """\t\tmkdir -p cache/contents.binary
\t\twget ${WGET_OPTIONS} ${LB_PARENT_MIRROR_CHROOT}/dists/${LB_PARENT_DISTRIBUTION}/Contents-${LB_ARCHITECTURES}.gz -O - | gunzip -c > cache/contents.binary/contents.${LB_PARENT_DISTRIBUTION}.${LB_ARCHITECTURES}
"""

new = """\t\tmkdir -p cache/contents.binary
\t\t# Debian trixie+: Contents lives in per-component subdirectories
\t\t: > cache/contents.binary/contents.${LB_PARENT_DISTRIBUTION}.${LB_ARCHITECTURES}
\t\tfor _CONTENTS_AREA in ${LB_PARENT_ARCHIVE_AREAS}
\t\tdo
\t\t\twget ${WGET_OPTIONS} ${LB_PARENT_MIRROR_CHROOT}/dists/${LB_PARENT_DISTRIBUTION}/${_CONTENTS_AREA}/Contents-${LB_ARCHITECTURES}.gz -O - | gunzip -c >> cache/contents.binary/contents.${LB_PARENT_DISTRIBUTION}.${LB_ARCHITECTURES} || true
\t\tdone
"""

if old not in src:
    print("❌ Förväntat block hittades inte — filen är kanske annorlunda. Avbryter utan ändring.")
    sys.exit(1)

src = src.replace(old, new, 1)
with open(path, "w") as f:
    f.write(src)
print("✅ Patchad: Contents hämtas nu per arkivkomponent (main, contrib, non-free, non-free-firmware).")
PY