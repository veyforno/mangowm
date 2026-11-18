#!/usr/bin/env bash
# usage: nowplaying.sh title | artist | icon

mode="$1"

# Pick a player: first "Playing", else first "Paused"
player=""
for want in Playing Paused; do
  for p in $(playerctl -l 2>/dev/null); do
    if [ "$(playerctl -p "$p" status 2>/dev/null)" = "$want" ]; then
      player="$p"
      break 2
    fi
  done
done

title="" artist="" status=""

if [ -n "$player" ]; then
  title=$(playerctl -p "$player" metadata title 2>/dev/null)
  artist=$(playerctl -p "$player" metadata artist 2>/dev/null)
  status=$(playerctl -p "$player" status 2>/dev/null)
elif command -v mpc >/dev/null 2>&1; then
  # Fallback for rmpc / MPD
  state=$(mpc status 2>/dev/null | sed -n '2p')
  case "$state" in
  *"[playing]"*) status="Playing" ;;
  *"[paused]"*) status="Paused" ;;
  esac
  if [ -n "$status" ]; then
    title=$(mpc current -f '%title%' 2>/dev/null)
    artist=$(mpc current -f '%artist%' 2>/dev/null)
    [ -z "$title" ] && title=$(mpc current -f '%file%' 2>/dev/null | xargs -0 basename 2>/dev/null)
  fi
fi

# Nothing playing -> print nothing
if [ -z "$status" ]; then
  case "$mode" in
  header) echo "Now Playing" ;;
  title) echo "Nothing Here . . ." ;;
  esac
  exit 0
fi

case "$mode" in
title) echo "${title:0:35}" ;;
artist) echo "${artist:0:35}" ;;
icon) [ "$status" = "Playing" ] && echo "⏸" || echo "▶" ;;
header) echo "Now Playing" ;;
esac
