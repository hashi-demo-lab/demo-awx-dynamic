#!/usr/bin/env bash
# Animated ASCII intro for the agentprovider AWX demo (recorded by VHS).
# AGENT / PROVIDER logo in Terraform purple (#7B42BC, truecolor) with a
# power-on flicker, line-by-line reveal, and a purple shimmer wave.
# Story: record a live API, validate the contract, run it — providers, dynamically.
set -u
ESC=$'\033'
P="$ESC[38;2;123;66;188m"      # Terraform purple
PB="$ESC[1;38;2;123;66;188m"   # bold Terraform purple
PL="$ESC[38;2;165;137;214m"    # light lavender
a="$ESC[38;2;120;100;160m"     # dim purple
G="$ESC[38;2;64;200;120m"      # phosphor green (proven)
C="$ESC[38;2;120;170;220m"     # cool blue accent
D=$'\033[2m'; B=$'\033[1m'; X=$'\033[0m'
HID="$ESC[?25l"; SHOW="$ESC[?25h"

# Purple shimmer ramp (truecolor r;g;b) — deep indigo → bright lavender.
PAL=("70;40;130" "94;53;177" "123;66;188" "140;90;210" "165;137;214" \
     "190;170;225" "216;200;242" "165;137;214" "140;90;210" "94;53;177")
NP=${#PAL[@]}

cleanup(){ printf '%b' "$SHOW$X"; }
trap cleanup EXIT

# --- exact logo art (verbatim) --------------------------------------------
mapfile -t BANNER <<'ART'
 █████╗  ██████╗ ███████╗███╗   ██╗████████╗
██╔══██╗██╔════╝ ██╔════╝████╗  ██║╚══██╔══╝
███████║██║  ███╗█████╗  ██╔██╗ ██║   ██║
██╔══██║██║   ██║██╔══╝  ██║╚██╗██║   ██║
██║  ██║╚██████╔╝███████╗██║ ╚████║   ██║
╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝  ╚═══╝   ╚═╝

██████╗ ██████╗  ██████╗ ██╗   ██╗██╗██████╗ ███████╗██████╗
██╔══██╗██╔══██╗██╔═══██╗██║   ██║██║██╔══██╗██╔════╝██╔══██╗
██████╔╝██████╔╝██║   ██║██║   ██║██║██║  ██║█████╗  ██████╔╝
██╔═══╝ ██╔══██╗██║   ██║╚██╗ ██╔╝██║██║  ██║██╔══╝  ██╔══██╗
██║     ██║  ██║╚██████╔╝ ╚████╔╝ ██║██████╔╝███████╗██║  ██║
╚═╝     ╚═╝  ╚═╝ ╚═════╝   ╚═══╝  ╚═╝╚═════╝ ╚══════╝╚═╝  ╚═╝
ART
NL=${#BANNER[@]}

printf '%b' "$HID"
clear
printf '\n'

# --- (1) CRT power-on flicker ---------------------------------------------
bar="$(printf '%*s' 60 '' | tr ' ' '─')"
for lvl in "60;40;100" "94;53;177" "123;66;188" "70;45;120" "140;90;210" "123;66;188"; do
  printf '\r  %b%s%b' "$ESC[38;2;${lvl}m" "$bar" "$X"; sleep 0.05
done
printf '\r\033[2K\n'
sleep 0.10

# --- (2) reveal logo line by line (Terraform purple) ----------------------
for line in "${BANNER[@]}"; do
  printf '  %b%s%b\n' "$PB" "$line" "$X"
  sleep 0.06
done
printf '  %b%bC L I%b\n' "$D" "$PL" "$X"

# --- (3) purple shimmer wave (per-line, multibyte-safe) -------------------
shimmer(){ local off="$1" i rgb
  printf '%b' "$ESC[$((NL+1))A"          # up to top of logo (incl CLI line)
  for ((i=0; i<NL; i++)); do
    rgb=${PAL[(((i+off)) % NP)]}
    printf '\r  %b%s%b\n' "$ESC[1;38;2;${rgb}m" "${BANNER[$i]}" "$X"
  done
  printf '\r  %b%bC L I%b\n' "$D" "$PL" "$X"
}
for off in 0 1 2 3 4 5 6 7 8 9; do shimmer "$off"; sleep 0.05; done
# settle to bold Terraform purple
printf '%b' "$ESC[$((NL+1))A"
for line in "${BANNER[@]}"; do printf '\r  %b%s%b\n' "$PB" "$line" "$X"; done
printf '\r  %b%bC L I%b\n' "$D" "$PL" "$X"
sleep 0.3

# --- (4) typewriter tagline -----------------------------------------------
typ(){ local s="$1" col="$2" d="${3:-0.02}" i; printf '  %b' "$col"
  for ((i=0;i<${#s};i++)); do printf '%s' "${s:i:1}"; sleep "$d"; done; printf '%b\n' "$X"; }
printf '\n'
typ "the agent-native CLI for dynamic Terraform provider generation" "$B$PL" 0.018
sleep 0.5

# --- (5) the message: agent-first, agent-browser analogy ------------------
printf '\n'
printf '  %blike agent-browser: an %b%b%b%s%b%b — but for Terraform providers.%b\n' "$D" "$X" "$B" "$PL" "agent skill with a CLI" "$X" "$D" "$X"
sleep 0.7
printf '  the %b%b%s%b skill drives the %b%b%s%b CLI%b\n' \
  "$B" "$PL" "agentprovider" "$X" "$B" "$PL" "agentprovider" "$X" "$X"
sleep 1.0

# --- (5b) the promise (paired with the outro's "for the agent" panel) -----
# One line setting up the three beats the outro then proves. The `next:`
# prefix marks generated-Go as roadmap; the outro mirrors the same `next:`.
printf '\n'
printf '  %b──%b  %b%b%s%b  %b·%b  %b%b%s%b  %b·%b  %b%b%s%b\n' \
  "$D$P" "$X" "$B" "$PL" "deterministic mapping: any HTTP API → Terraform provider" "$X" "$D" "$X" "$B" "$PL" "YAML now" "$X" "$D" "$X" "$B" "$PL" "Go next" "$X"
sleep 0.9

# --- (6) pipeline + proven pulse ------------------------------------------
printf '\n  '
steps=("record" "conform" "completeness" "run")
for i in 0 1 2 3; do
  [ "$i" -gt 0 ] && { printf '%b  ─▶  %b' "$D" "$X"; sleep 0.16; }
  printf '%b%b%s%b' "$B" "$PL" "${steps[$i]}" "$X"; sleep 0.3
done
printf '\n\n'
on="  ${a}loop until ${X}${B}${G}✓ proven${X}"
off="  ${a}loop until ${X}${D}  proven${X}"
for i in 1 2 3; do
  printf '\r%b\033[K' "$on";  sleep 0.16
  printf '\r%b\033[K' "$off"; sleep 0.10
done
printf '\r%b\033[K\n' "$on"
sleep 1.1
