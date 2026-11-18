#!/usr/bin/env python3
"""Talk to MPD (the daemon rmpc controls) and print one JSON line whenever the
playing state, track or current lyric line changes.

Lyrics are read from .lrc files. Lookup order for a song "Artist/Album/x.flac":
  $MUSIC_DIR/Artist/Album/x.lrc
  $LYRICS_DIR/Artist/Album/x.lrc
  $LYRICS_DIR/x.lrc
  $LYRICS_DIR/<Artist> - <Title>.lrc
Set LYRICS_DIR to the same folder as `lyrics_dir` in your rmpc config.
"""
import bisect
import json
import os
import re
import socket
import sys
import time
from pathlib import Path

POLL = 0.2
MUSIC_DIR = Path(os.environ.get("MUSIC_DIR", "~/Music")).expanduser()
LYRICS_DIR = Path(os.environ.get("LYRICS_DIR", "~/.config/rmpc/lyrics")).expanduser()
LEAD = float(os.environ.get("LYRIC_LEAD", "0.15"))  # show lines slightly early

TS = re.compile(r"\[(\d+):(\d+(?:[.:]\d+)?)\]")
OFFSET = re.compile(r"\[offset:\s*([+-]?\d+)\]", re.I)


class MPD:
    def __init__(self):
        host = os.environ.get("MPD_HOST", "localhost")
        port = int(os.environ.get("MPD_PORT", "6600"))
        password = None
        if "@" in host:
            password, host = host.split("@", 1)
        if host.startswith(("/", "~")):
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(3)
            s.connect(os.path.expanduser(host))
        else:
            s = socket.create_connection((host, port), timeout=3)
        self.s = s
        self.r = s.makefile("r", encoding="utf-8", errors="replace", newline="\n")
        if not self.r.readline().startswith("OK MPD"):
            raise OSError("not an MPD server")
        if password:
            self.cmd(f"password {password}")

    def cmd(self, c):
        self.s.sendall((c + "\n").encode())
        out = {}
        for line in self.r:
            line = line.rstrip("\n")
            if line == "OK":
                return out
            if line.startswith("ACK"):
                raise OSError(line)
            k, _, v = line.partition(": ")
            out[k] = v
        raise OSError("connection closed")


def parse_lrc(path):
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return [], []
    off = OFFSET.search(text)
    offset = int(off.group(1)) / 1000 if off else 0.0
    rows = []
    for raw in text.splitlines():
        stamps = TS.findall(raw)
        if not stamps:
            continue
        body = TS.sub("", raw).strip()
        for mm, ss in stamps:
            rows.append((int(mm) * 60 + float(ss.replace(":", ".")) - offset, body))
    rows.sort(key=lambda r: r[0])
    return [r[0] for r in rows], [r[1] for r in rows]


def candidates(song):
    rel = Path(song.get("file", "")).with_suffix(".lrc")
    yield MUSIC_DIR / rel
    yield LYRICS_DIR / rel
    yield LYRICS_DIR / rel.name
    a, t = song.get("Artist", ""), song.get("Title", "")
    if a and t:
        yield LYRICS_DIR / f"{a} - {t}.lrc"


def load_lyrics(song):
    for p in candidates(song):
        if p.is_file():
            times, lines = parse_lrc(p)
            if times:
                return times, lines
    return [], []


def emit(payload, last):
    if payload != last:
        try:
            print(json.dumps(payload, ensure_ascii=False), flush=True)
        except BrokenPipeError:
            sys.exit(0)
    return payload


def blank(state="stop"):
    return {"state": state, "title": "", "artist": "", "album": "",
            "prev": "", "line": "", "next": "", "hasLyrics": False}


def main():
    client = None
    last = None
    cache_file, times, lines = None, [], []
    while True:
        payload = None
        try:
            if client is None:
                client = MPD()
            st = client.cmd("status")
            state = st.get("state", "stop")
            if state in ("play", "pause"):
                song = client.cmd("currentsong")
                if song.get("file") != cache_file:
                    cache_file = song.get("file")
                    times, lines = load_lyrics(song)
                payload = blank(state)
                payload["title"] = song.get("Title") or Path(song.get("file", "")).stem
                payload["artist"] = song.get("Artist", "")
                payload["album"] = song.get("Album", "")
                if times:
                    elapsed = float(st.get("elapsed", 0))
                    i = bisect.bisect_right(times, elapsed + LEAD) - 1
                    payload["hasLyrics"] = True
                    payload["prev"] = lines[i - 1] if i >= 1 else ""
                    payload["line"] = lines[i] if i >= 0 else ""
                    payload["next"] = lines[i + 1] if i + 1 < len(lines) else ""
            else:
                cache_file = None
                payload = blank("stop")
        except (OSError, ValueError):
            client = None
            payload = blank("stop")
            last = emit(payload, last)
            time.sleep(1)
            continue
        last = emit(payload, last)
        time.sleep(POLL)


if __name__ == "__main__":
    main()
