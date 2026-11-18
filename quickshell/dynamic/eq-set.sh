#!/bin/sh
# Atur gain equalizer PipeWire.
# Pemakaian:  eq-set.sh 1=3.0 2=-2.5 3=0.0 ...   (nomor band = gain dalam dB)

# simpan nilai terakhir supaya slider ingat posisinya setelah quickshell di-restart
mkdir -p "$HOME/.local/state"
echo "$@" > "$HOME/.local/state/dynamic-eq"

# susun parameter: "eq_band_1:Gain" 3.0 "eq_band_2:Gain" -2.5 ...
params=""
for pair in "$@"; do
  band=${pair%%=*}
  gain=${pair#*=}
  params="$params \"eq_band_${band}:Gain\" $gain"
done

# cari id node EQ (sisi input & output), lalu kirim parameternya
for name in effect_input.eq effect_output.eq; do
  id=$(pw-cli ls Node | awk -v n="$name" '
    $1 == "id" { gsub(",", "", $2); id = $2 }
    $1 == "node.name" && $3 == "\"" n "\"" { print id; exit }')
  [ -n "$id" ] && pw-cli s "$id" Props "{ params = [ $params ] }" >/dev/null 2>&1
done
exit 0
