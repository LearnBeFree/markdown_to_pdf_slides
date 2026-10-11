#!/usr/bin/env bash
# tests/make-assets.sh — deterministic tiny images for the test corpus.
# Pure python3 stdlib (zlib/struct): no network, no PIL. Byte-stable output.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/assets"
mkdir -p "$DIR"

python3 - "$DIR" <<'PY'
import struct, sys, zlib, base64, shutil
out = sys.argv[1]

def png(path, w, h, rgb):
    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c))
    raw = b"".join(b"\x00" + bytes(rgb) * w for _ in range(h))
    body = (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))
    open(f"{out}/{path}", "wb").write(body)

png("portrait.png", 2, 6, (200, 30, 30))    # ar 0.33 -> side column
png("landscape.png", 6, 2, (30, 120, 200))  # ar 3.0  -> bottom band
png("square.png", 4, 4, (30, 160, 60))
png("картинка.png", 6, 2, (160, 30, 160))   # unicode filename

# tiny real JPEG (1x1 gray)
open(f"{out}/tiny.jpg", "wb").write(base64.b64decode(
    "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRof"
    "Hh0aHBwcJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPDs0NDT/wAALCAABAAEBAREA/8QAFAAB"
    "AAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AVN//2Q=="))

# tiny real GIF (1x1 transparent)
open(f"{out}/tiny.gif", "wb").write(base64.b64decode(
    "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"))

# PNG bytes deliberately mislabeled as .jpg (extension/content mismatch case)
shutil.copyfile(f"{out}/landscape.png", f"{out}/mislabeled.jpg")
PY

cat > "$DIR/note.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="60" height="20"><rect width="60" height="20" fill="teal"/></svg>
SVG

echo "assets: $(ls "$DIR" | wc -l) files in $DIR"
