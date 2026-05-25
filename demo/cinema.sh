#!/usr/bin/env bash
# agentprovider author->prove loop — ascii cinema. Recorded with asciinema.
set -u
A=$'\033[38;5;214m'   # amber
a=$'\033[38;5;130m'   # dim amber
G=$'\033[38;5;42m'    # phosphor green (pass)
R=$'\033[38;5;203m'   # red (fail)
C=$'\033[38;5;81m'    # cyan accent
D=$'\033[2m'; B=$'\033[1m'; X=$'\033[0m'
HID=$'\033[?25l'; SHOW=$'\033[?25h'

p(){ printf '%b\n' "$1"; }
pause(){ sleep "$1"; }
# typewriter for command lines (streams live)
typ(){ local s="$1" d="${2:-0.03}" i; printf '%b' "$A"; for ((i=0;i<${#s};i++)); do printf '%s' "${s:i:1}"; sleep "$d"; done; printf '%b\n' "$X"; }
# streamed result line
res(){ printf '   %b%s%b  %b%s%b\n' "$D" "$1" "$X" "$G" "$2" "$X"; sleep 0.22; }

printf '%b' "$HID"
clear
pause 0.3
# --- hero banner ---
printf '%b%b\n' "$B" "$A"
python3 "$(dirname "$0")/banner.py" AGENTPROVIDER
printf '%b' "$X"
pause 0.2
p ""
p "   ${a}AI authors a Terraform provider —${X} ${A}${B}and proves it.${X}"
p "   ${D}one declarative YAML contract · one generic engine · zero hand-written Go${X}"
pause 1.0
p ""
p "   ${C}··· est. lineage: 1969 — ARPANET, Apollo, the dawn of Unix ···${X}"
pause 1.1
p ""

# --- the loop ---
p "${a}┌─ the author → prove loop ───────────────────────────────────┐${X}"; pause 0.2
p "${a}│${X}                                                             ${a}│${X}"; pause 0.15
p "${a}│${X}   ${A}bootstrap${X} ${D}─▶${X} ${A}record${X} ${D}─▶${X} ${A}conform${X} ${D}─▶${X} ${A}repair_hints${X}        ${a}│${X}"; pause 0.25
p "${a}│${X}      ${D}seed${X}        ${D}cassette${X}     ${D}verdict${X}        ${D}self-correct${X}    ${a}│${X}"; pause 0.25
p "${a}│${X}                                ${D}│${X}              ${D}▲${X}            ${a}│${X}"; pause 0.15
p "${a}│${X}                                ${D}└──── loop until ──────┘${X}        ${a}│${X}"; pause 0.2
p "${a}│${X}                                 ${G}overall_passed ✓${X}              ${a}│${X}"; pause 0.2
p "${a}│${X}                                                             ${a}│${X}"; pause 0.1
p "${a}└─────────────────────────────────────────────────────────────┘${X}"
pause 1.0
p ""

# --- a run ---
printf '%b' "${D}\$ ${X}"
typ 'agentprovider conform contracts/item.yaml fixtures/crudcrud --json' 0.018
pause 0.4
p "${D}   replaying byte-accurate recorded responses …${X}"
pause 0.7
res "id_is_computed_and_nonempty" "PASS"
res "create_echoes_inputs       " "PASS"
res "read_matches_create        " "PASS"
res "update_then_read_reflects  " "PASS"
res "second_apply_is_noop       " "PASS"
res "delete_then_read_404       " "PASS"
pause 0.3
p ""
p "   ${B}${G}overall_passed: true${X}   ${G}6/6 invariants${X}   ${D}— the contract is proven.${X}"
pause 1.3
p ""

# --- the hardening flourish ---
p "${a}eval-hardened over 10 rounds:${X}"; pause 0.25
p "   ${A}▮▮▮▮▮▮▮▮▮▮${X} ${D}pass rate${X}   ${R}4/5${X} ${D}─▶${X} ${G}5/5${X}"; pause 0.3
p "   ${A}▮▮▮▮▮▯▯▯▯▯${X} ${D}tokens${X}      ${a}280k${X} ${D}─▶${X} ${A}155k${X}  ${D}(−45%)${X}"; pause 0.3
p "   ${A}▮▮▮▮▮▮▮▮▮▮${X} ${D}core fixes${X}  ${A}5${X} ${D}· each codex-authored, xhigh-reviewed${X}"; pause 0.3
p "   ${A}▮▮▮▮▮▮▮▮▮▮${X} ${D}new gates${X}   ${A}read_returns_expected · ephemeral_open_renew_close${X}"; pause 0.9
p ""
p "   ${B}${A}contract authored.  contract proven.  ▮${X}"
pause 1.6
printf '%b' "$SHOW"
