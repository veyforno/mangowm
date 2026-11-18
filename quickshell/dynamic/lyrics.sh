#!/bin/bash
# Cari file lirik .lrc untuk sebuah lagu (dipakai island musik).
# usage: lyrics.sh <file-relatif-mpd> [musicDir] [lyricsDir]
# Mencari <lyricsDir>/<lagu>.lrc  lalu  <musicDir>/<lagu>.lrc  (nama sama dengan lagu, ekstensi .lrc)
f="$1"; md="$2"; ld="$3"
[ -z "$f" ] && exit 0
if [ -z "$md" ]; then
    md=$(sed -n 's/^[[:space:]]*music_directory[[:space:]]*"\(.*\)".*/\1/p' "$HOME/.config/mpd/mpd.conf" /etc/mpd.conf 2>/dev/null | head -n1)
fi
md="${md/#\~/$HOME}"; ld="${ld/#\~/$HOME}"
[ -z "$ld" ] && ld="$md"
base="${f%.*}"
for p in "$ld/$base.lrc" "$md/$base.lrc" "$ld/$(basename "$base").lrc"; do
    [ -f "$p" ] && { cat "$p"; exit 0; }
done
exit 0
