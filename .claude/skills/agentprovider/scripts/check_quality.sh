#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../../../.." && pwd)
skill_dir="$repo_root/.agents/skills/agentprovider"

fail() {
  printf 'agentprovider skill quality check failed: %s\n' "$1" >&2
  exit 1
}

line_count=$(wc -l < "$skill_dir/SKILL.md" | tr -d ' ')
if [ "$line_count" -gt 500 ]; then
  fail "SKILL.md has $line_count lines; keep the loaded body at or below 500"
fi

for json in "$skill_dir"/evals/*.json; do
  jq empty "$json" || fail "invalid JSON: $json"
done

for shell_script in "$skill_dir"/scripts/*.sh; do
  [ -e "$shell_script" ] || continue
  sh -n "$shell_script" || fail "invalid shell syntax: $shell_script"
done

jq -e -s '(.[0].metric_schema | keys) == (.[1].metric_schema | keys)' \
  "$skill_dir/evals/awx-lean.json" \
  "$skill_dir/evals/awx-live.json" >/dev/null ||
  fail "awx-lean.json and awx-live.json metric_schema keys differ"

generic_docs=$(find "$skill_dir/references" -type f -name '*.md' -print)
if rg -n 'AWX|awx_|aap_|job_template|workflow_job_template|localhost:30080' "$skill_dir/SKILL.md" $generic_docs >/dev/null; then
  rg -n 'AWX|awx_|aap_|job_template|workflow_job_template|localhost:30080' "$skill_dir/SKILL.md" $generic_docs >&2
  fail "SKILL.md or generic references contain target-specific AWX examples; keep those in evals/docs"
fi

for required in \
  'bootstrap --from-introspect' \
  'agentprovider prove' \
  'completeness' \
  'mutation-check' \
  'emit-proof' \
  'green-washing' \
  'PROVEN' \
  'references/gotchas.md' \
  'references/terraform-usage.md'
do
  rg -q "$required" "$skill_dir/SKILL.md" ||
    fail "SKILL.md is missing required guidance: $required"
done

printf 'agentprovider skill quality check passed: SKILL.md=%s lines, eval JSON valid, metric schemas aligned\n' "$line_count"
