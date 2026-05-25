#!/usr/bin/env bash
# Closing card for the agentprovider AWX demo (recorded by VHS): a green recap,
# a "THE END" banner in Terraform purple with a shimmer wave, and a tagline.
set -u
ESC=$'\033'
P="$ESC[38;2;123;66;188m"      # Terraform purple
PB="$ESC[1;38;2;123;66;188m"   # bold Terraform purple
PL="$ESC[38;2;165;137;214m"    # light lavender
G="$ESC[38;2;64;200;120m"      # phosphor green
D=$'\033[2m'; B=$'\033[1m'; X=$'\033[0m'
HID="$ESC[?25l"; SHOW="$ESC[?25h"

PAL=("70;40;130" "94;53;177" "123;66;188" "140;90;210" "165;137;214" \
     "190;170;225" "216;200;242" "165;137;214" "140;90;210" "94;53;177")
NP=${#PAL[@]}

cleanup(){ printf '%b' "$SHOW$X"; }
trap cleanup EXIT

printf '%b' "$HID"
clear
printf '\n'

# --- recap: what the agent just did ---------------------------------------
printf '  %b✓%b  inventory resource     %b%bagentprovider conform%b  →  %b6/6 invariants%b\n' "$G$B" "$X" "$D" "" "$X" "$G" "$X"; sleep 0.45
printf '  %b✓%b  job-launch action      %b%bagentprovider conform%b  →  %baction_returns_expected%b\n' "$G$B" "$X" "$D" "" "$X" "$G" "$X"; sleep 0.45
printf '  %b✓%b  terraform apply        %b%blive AWX%b  →  %binventory created · job launched%b\n' "$G$B" "$X" "$D" "" "$X" "$G" "$X"; sleep 0.7
printf '\n\n'

# --- THE END banner (reveal + purple shimmer) -----------------------------
mapfile -t BANNER < <(figlet -f standard "THE END" 2>/dev/null)
NL=${#BANNER[@]}
for line in "${BANNER[@]}"; do printf '  %b%s%b\n' "$PB" "$line" "$X"; sleep 0.06; done
shimmer(){ local off="$1" i rgb
  printf '%b' "$ESC[${NL}A"
  for ((i=0;i<NL;i++)); do rgb=${PAL[(((i+off)) % NP)]}; printf '\r  %b%s%b\n' "$ESC[1;38;2;${rgb}m" "${BANNER[$i]}" "$X"; done
}
for off in 0 1 2 3 4 5 6 7 8 9; do shimmer "$off"; sleep 0.05; done
printf '%b' "$ESC[${NL}A"
for line in "${BANNER[@]}"; do printf '\r  %b%s%b\n' "$PB" "$line" "$X"; done

# --- closing tagline ------------------------------------------------------
printf '\n'
printf '  %bagentprovider%b  %b·%b  agent-first Terraform provider generation\n' "$PB" "$X" "$D" "$X"
sleep 0.4
printf '  %bthe agentprovider-author skill drives the agentprovider CLI — record · validate · run%b\n' "$D" "$X"
sleep 1.6
