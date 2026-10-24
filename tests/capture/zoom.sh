#!/bin/bash
# zoom.sh DIR GEOMETRY OUT NAME... : crop GEOMETRY (WxH+X+Y) from DIR/NAME.png
# for each NAME, scale 2x, and lay them side by side in OUT.
set -eu
DIR=$1 GEOM=$2 OUTFILE=$3
shift 3
TMP=$(mktemp -d)
i=0
for name in "$@"; do
  magick "$DIR/$name.png" -crop "$GEOM" +repage -scale 200% \
    -gravity north -background '#202020' -splice 0x28 -fill white -pointsize 18 -annotate +0+4 "$name" \
    "$TMP/$i.png"
  i=$((i + 1))
done
magick "$TMP"/*.png +append "$OUTFILE"
rm -rf "$TMP"
