#!/usr/bin/env bash
# Syntax-highlighted code snippet for the demo.
#   demo/show.sh <lang> <file> <sed-range>
# <lang> is a Pygments lexer (yaml | terraform); <sed-range> is any sed line
# range, numeric ("19,33") or pattern ("/^actions:/,/expect_status/").
# Falls back to plain sed if pygmentize is unavailable.
set -euo pipefail
lang="$1"; file="$2"; range="$3"
if command -v pygmentize >/dev/null 2>&1; then
  sed -n "${range}p" "$file" | pygmentize -l "$lang" -f terminal16m -O style=dracula
else
  sed -n "${range}p" "$file"
fi
