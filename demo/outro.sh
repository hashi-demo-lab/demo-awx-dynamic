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
printf '  %b✓%b  bootstrap              %b%bagentprovider bootstrap --response%b  →  %bseeded draft contract%b\n' "$G$B" "$X" "$D" "" "$X" "$G" "$X"; sleep 0.40
printf '  %b✓%b  record                 %b%bagentprovider record%b  →  %bbyte-accurate cassette (go-vcr) + redacted auth%b\n' "$G$B" "$X" "$D" "" "$X" "$G" "$X"; sleep 0.40
printf '  %b✓%b  conform inventory      %b%bagentprovider conform%b  →  %b8/8 invariants%b\n' "$G$B" "$X" "$D" "" "$X" "$G" "$X"; sleep 0.40
printf '  %b✓%b  completeness gate      %b%b--min-completeness 90%b  →  %b100%% of the live API surface%b\n' "$G$B" "$X" "$D" "" "$X" "$G" "$X"; sleep 0.40
printf '  %b✓%b  conform action         %b%bagentprovider conform%b  →  %baction_returns_expected · state_matches_expect%b\n' "$G$B" "$X" "$D" "" "$X" "$G" "$X"; sleep 0.40
printf '  %b✓%b  terraform apply        %b%blive AWX%b  →  %binventory created · job launched%b\n' "$G$B" "$X" "$D" "" "$X" "$G" "$X"; sleep 0.70
printf '\n'

# --- for the agent authoring this -----------------------------------------
# Bullet content locked by the plan at ~/.claude/plans/foamy-gathering-crown.md.
# Visual grammar: dim rule + lavender claim + dim explanation, inverting the
# recap's green-check pattern so the panels read as distinct sections.
printf '  %b──  for the agent authoring this  ──────────────────────────────────%b\n' "$D$P" "$X"; sleep 0.30
printf '  %b•%b  %bdeterministic mapping%b              %b— any HTTP API → Terraform provider, in YAML%b\n' "$PL" "$X" "$PL" "$X" "$D" "$X"; sleep 0.40
printf '  %b•%b  %bone engine, many contracts%b         %b— no per-API Go to write%b\n' "$PL" "$X" "$PL" "$X" "$D" "$X"; sleep 0.40
printf '  %b•%b  %bbyte-accurate replay (go-vcr)%b      %b— record once, prove; deterministic CI%b\n' "$PL" "$X" "$PL" "$X" "$D" "$X"; sleep 0.40
printf '  %b•%b  %bthe contract carries its own proof%b %b— conform returns a verdict; repair_hints self-correct%b\n' "$PL" "$X" "$PL" "$X" "$D" "$X"; sleep 0.40
printf '  %b%bnext:%b %bpromote contracts into a generated Go provider%b\n' "  " "$D" "$X" "$PL" "$X"; sleep 0.60
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
printf '  %bthe agentprovider skill drives the agentprovider CLI — record · validate · check completeness · run%b\n' "$D" "$X"
sleep 1.6
