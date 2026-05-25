#!/usr/bin/env bash
# Pretty one-screen conformance verdict for the VHS demo: runs `agentprovider
# conform <contract> <cassette> --json` and renders the per-invariant pass/fail
# plus overall_passed. Keeps the tape's command line short and readable.
set -euo pipefail
agentprovider conform "$1" "$2" --json | jq -r '
  (.results[] | "  " + (if .passed then "[32m✓ PASS[0m" else "[31m✗ FAIL[0m" end) + "  " + .name),
  "",
  "  overall_passed: " + (if .overall_passed then "[1;32mtrue[0m" else "[1;31mfalse[0m" end)'
