#!/bin/bash
# Ambil cover album dari MPD (dipakai island musik).
# usage: art.sh <output-path> <file-relatif-mpd>
out="$1"; f="$2"
[ -z "$f" ] && exit 0
mpc readpicture "$f" > "$out" 2>/dev/null                     # cover yang tertanam di tag
[ -s "$out" ] || mpc albumart "$f" > "$out" 2>/dev/null       # cover.jpg / folder.jpg di folder lagu
[ -s "$out" ] || { rm -f "$out"; exit 0; }
for o in /tmp/dynamic-art-*; do [ "$o" != "$out" ] && rm -f "$o"; done   # bersihkan cover lama
echo "$out"
