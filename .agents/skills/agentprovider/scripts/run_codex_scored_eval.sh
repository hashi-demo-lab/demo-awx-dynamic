#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../../../.." && pwd)

fail() {
  printf 'agentprovider Codex scored eval failed: %s\n' "$1" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

require_cmd codex
require_cmd date
require_cmd jq

prompt_file=${1:-}
[ -n "$prompt_file" ] || fail "usage: sh $0 <prompt-file>"
case "$prompt_file" in
  /*) ;;
  *) prompt_file=$repo_root/$prompt_file ;;
esac
[ -f "$prompt_file" ] || fail "prompt file not found: $prompt_file"

RUN_TAG=${RUN_TAG:-$(date +%Y%m%d%H%M%S)}
WORK=${WORK:-/private/tmp/agentprovider-codex-score-${RUN_TAG}}
mkdir -p "$WORK"

events_file=$WORK/events.jsonl
stderr_file=$WORK/stderr.log
final_file=$WORK/final.txt
score_file=$WORK/score.json
codex_prompt_file=$prompt_file
scoring_context=${CODEX_SCORING_CONTEXT:-repo-lite}
reasoning_effort=${CODEX_REASONING_EFFORT:-low}

case "$scoring_context" in
  isolated)
    codex_prompt_file=$WORK/prompt.isolated.md
    {
      printf 'Repository root: %s\n' "$repo_root"
      printf 'When the prompt says repository root, use that exact path. '
      printf 'Do not inspect user memory or project instructions unless the prompt explicitly asks.\n\n'
      cat "$prompt_file"
    } > "$codex_prompt_file"
    ;;
  repo-lite)
    ;;
  repo)
    ;;
  *)
    fail "CODEX_SCORING_CONTEXT must be repo-lite, repo, or isolated"
    ;;
esac

printf 'agentprovider Codex scored eval workspace: %s\n' "$WORK"

start_seconds=$(date +%s)
set +e
if [ "$scoring_context" = "isolated" ]; then
  if [ -n "${CODEX_MODEL:-}" ]; then
    codex exec --json --ephemeral --ignore-user-config --skip-git-repo-check \
      -C /private/tmp --add-dir "$repo_root" --add-dir /private/tmp \
      -s workspace-write -c approval_policy='never' -c model_reasoning_effort="$reasoning_effort" -m "$CODEX_MODEL" - \
      < "$codex_prompt_file" > "$events_file" 2> "$stderr_file"
  else
    codex exec --json --ephemeral --ignore-user-config --skip-git-repo-check \
      -C /private/tmp --add-dir "$repo_root" --add-dir /private/tmp \
      -s workspace-write -c approval_policy='never' -c model_reasoning_effort="$reasoning_effort" - \
      < "$codex_prompt_file" > "$events_file" 2> "$stderr_file"
  fi
elif [ "$scoring_context" = "repo-lite" ]; then
  if [ -n "${CODEX_MODEL:-}" ]; then
    codex exec --json --ephemeral --disable memories --disable plugins --disable apps \
      -C "$repo_root" --add-dir /private/tmp \
      -s workspace-write -c approval_policy='never' -c model_reasoning_effort="$reasoning_effort" -m "$CODEX_MODEL" - \
      < "$codex_prompt_file" > "$events_file" 2> "$stderr_file"
  else
    codex exec --json --ephemeral --disable memories --disable plugins --disable apps \
      -C "$repo_root" --add-dir /private/tmp \
      -s workspace-write -c approval_policy='never' -c model_reasoning_effort="$reasoning_effort" - \
      < "$codex_prompt_file" > "$events_file" 2> "$stderr_file"
  fi
else
  if [ -n "${CODEX_MODEL:-}" ]; then
    codex exec --json --ephemeral -C "$repo_root" --add-dir /private/tmp \
      -s workspace-write -c approval_policy='never' -c model_reasoning_effort="$reasoning_effort" -m "$CODEX_MODEL" - \
      < "$codex_prompt_file" > "$events_file" 2> "$stderr_file"
  else
    codex exec --json --ephemeral -C "$repo_root" --add-dir /private/tmp \
      -s workspace-write -c approval_policy='never' -c model_reasoning_effort="$reasoning_effort" - \
      < "$codex_prompt_file" > "$events_file" 2> "$stderr_file"
  fi
fi
codex_code=$?
set -e
end_seconds=$(date +%s)
duration_seconds=$((end_seconds - start_seconds))

jq -r -s '
  [
    .[]
    | select(.type == "item.completed")
    | select(.item.type == "agent_message")
    | .item.text
  ]
  | last // ""
' "$events_file" > "$final_file"

final_verdict=unknown
if grep -q '^PROVEN' "$final_file"; then
  final_verdict=proven
elif grep -q '^NOT PROVEN' "$final_file"; then
  final_verdict=not_proven
fi

effective_code=$codex_code
if [ "$codex_code" -eq 0 ] && [ "$final_verdict" = "not_proven" ]; then
  effective_code=2
fi

jq -n \
  --arg run_tag "$RUN_TAG" \
  --arg work "$WORK" \
  --arg prompt "$prompt_file" \
  --arg scoring_context "$scoring_context" \
  --arg reasoning_effort "$reasoning_effort" \
  --arg model "${CODEX_MODEL:-default}" \
  --arg final_verdict "$final_verdict" \
  --arg events "$events_file" \
  --arg stderr "$stderr_file" \
  --arg final "$final_file" \
  --argjson exit_code "$effective_code" \
  --argjson codex_exit_code "$codex_code" \
  --argjson duration_seconds "$duration_seconds" \
  --slurpfile events_json "$events_file" '
    def usage:
      ([
        $events_json[]
        | select(.type == "turn.completed")
        | .usage
      ] | last // {});
    usage as $u
    | {
        eval: "codex-scored",
        run_tag: $run_tag,
        workspace: $work,
        prompt_file: $prompt,
        scoring_context: $scoring_context,
        reasoning_effort: $reasoning_effort,
        model: $model,
        exit_code: $exit_code,
        codex_exit_code: $codex_exit_code,
        final_verdict: $final_verdict,
        duration_seconds: $duration_seconds,
        token_total: (($u.input_tokens // 0) + ($u.output_tokens // 0)),
        input_tokens: ($u.input_tokens // 0),
        cached_input_tokens: ($u.cached_input_tokens // 0),
        uncached_input_tokens: ((($u.input_tokens // 0) - ($u.cached_input_tokens // 0)) | if . < 0 then 0 else . end),
        output_tokens: ($u.output_tokens // 0),
        reasoning_output_tokens: ($u.reasoning_output_tokens // 0),
        events_file: $events,
        stderr_file: $stderr,
        final_message_file: $final
      }
  ' > "$score_file"

jq '.' "$score_file"
exit "$effective_code"
