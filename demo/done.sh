#!/usr/bin/env bash
# Sentinel script run by the agent at the end of a demo session.
# Prints DEMO_COMPLETE to stdout so VHS Wait+Screen can match it,
# then writes a timestamped marker file for external tooling.
set -u
MARKER="${1:-/tmp/awx-demo-done}"
printf '%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$MARKER"
printf 'DEMO_COMPLETE\n'
