#!/bin/sh
# Compare plugin output with the Python extractor: same mapping, index and pattern?
# usage: ./compare.sh rows.txt ../sail-extract/out/encdec_patterns.txt
awk '{print $1, $2, $3}' "$1" > /tmp/plugin.txt
awk '/^## /{m=$2} /^ *[0-9]+  /{gsub(/\?/,"-",$2); print m, $1, $2}' "$2" > /tmp/script.txt
diff /tmp/script.txt /tmp/plugin.txt && echo "IDENTIEK"
