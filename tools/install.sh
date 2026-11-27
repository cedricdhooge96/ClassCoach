#!/bin/sh
# Copies the addon into the game's AddOns folder, then reads the installed copy
# back and compares it with the repository (workflow steps 4 and 5).
# An install once reported success while it wrote an old copy of a file, so the
# comparison is the proof, not the copy.
#
#   tools/install.sh                 the default WoW Forever folder, seen from WSL
#   ADDONS=/path/to/AddOns tools/install.sh
set -eu
cd "$(dirname "$0")/.."
ADDONS="${ADDONS:-/mnt/c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns}"
if [ ! -d "$ADDONS" ]; then
  echo "AddOns folder not found: $ADDONS (set ADDONS=...)" >&2
  exit 1
fi
DEST="$ADDONS/ClassCoach"
# A file that is new in this install needs a full game restart; /reload does not load it.
added=$(cd ClassCoach && find . -type f | while read -r f; do [ -e "$DEST/$f" ] || echo "$f"; done)
mkdir -p "$DEST"
# --checksum: the Windows clock and the file sizes are not trusted to show a change.
rsync -r --delete --checksum ClassCoach/ "$DEST/"
if ! diff -r ClassCoach "$DEST" >/dev/null; then
  echo "INSTALL FAILED: the installed copy differs from the repository:" >&2
  diff -rq ClassCoach "$DEST" >&2 || true
  exit 1
fi
version=$(sed -n 's/^## Version: *//p' ClassCoach/ClassCoach.toc | tr -d '\r')
echo "Installed ClassCoach $version; the installed copy matches the repository."
if [ -n "$added" ]; then
  echo "New files (restart the game, /reload is not enough):"
  echo "$added"
else
  echo "Type /reload in the game."
fi
