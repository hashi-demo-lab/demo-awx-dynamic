# agentprovider AWX demo v5 (VHS) — live Claude Code user experience.
# Same shape as v4, with two changes:
#   1. Fixed Sleep 25m for the agent work window (a take runs ~18-20m).
#   2. One concurrent Sonnet 4.6 medium-effort subagent per contract so every
#      contract is built in parallel and the full 16-contract scope is covered.
#
# Outputs mp4 directly (VHS-native h264) — gif palettegen chokes on long
# (12+ min) captures. Must be run in a FOREGROUND terminal (not backgrounded):
# VHS spawns ttyd which needs a controlling terminal — a backgrounded run gets
# SIGTTOU'd and stops. Use demo/record-awx.sh, which runs vhs in the foreground.
#
# Scope: fresh contracts for organization, inventory, job template, and host
# resources; a data source; job-launch and workflow-job-launch actions; then a
# real Terraform init/apply/plan using terraform-provider-dynamic.
#
# Render manually with:
#   demo/record-awx.sh demo/agentprovider-awx-v5.tape
#
# Needs local AWX-on-Docker/kind, Claude Code auth, and the repo-local
# agentprovider and terraform-provider-dynamic binaries.
Output demo/agentprovider-awx-v5.mp4

Set Shell bash
Set Framerate 12
Set FontSize 18
Set Width 1500
Set Height 860
Set Padding 24
Set Theme "Catppuccin Mocha"
Set WindowBar Colorful
Set TypingSpeed 27ms

# --- setup (hidden): put the repo-local binaries on PATH, configure local AWX
#     credentials without printing .env, point Terraform at the local provider
#     binary, define the `clauded` alias (claude --dangerously-skip-permissions),
#     and keep the shell prompt short for the recording. ---
Hide
Type "cd /Users/simon.lynch/git/demo-awx-dynamic" Enter
Type "export PATH=$PWD/demo/bin:$PWD:$PATH" Enter
Type "set -a; source .env; set +a" Enter
Type "export AWX=${AWX:-http://localhost:30080}" Enter
Type "export AWX_USERNAME=${AWX_USERNAME:-admin}" Enter
Type "export AWX_PASSWORD=${AWX_PASSWORD:-$(cat demo/awx/.admin_password)}" Enter
Type "export AGENTPROVIDER_CONTRACTS=$PWD/.agentprovider/contracts" Enter
Type "mkdir -p demo/awx/tf/bin" Enter
Type "if [ ! -x demo/awx/tf/bin/terraform-provider-dynamic ] && [ -x terraform-provider-dynamic ]; then cp terraform-provider-dynamic demo/awx/tf/bin/terraform-provider-dynamic; fi" Enter
Type `printf 'provider_installation {\n  dev_overrides {\n    "hashicorp/dynamic" = "%s"\n  }\n  direct {}\n}\n' "$PWD/demo/awx/tf/bin" > /tmp/awx-dev.tfrc` Enter
Type "export TF_CLI_CONFIG_FILE=/tmp/awx-dev.tfrc" Enter
Type "rm -rf .agentprovider/contracts .agentprovider/cassettes .agentprovider/schemas .agentprovider/metadata" Enter
Type "mkdir -p .agentprovider/contracts .agentprovider/cassettes" Enter
Type "rm -rf examples/awx demo/awx/tf/.terraform demo/awx/tf/terraform.tfstate demo/awx/tf/terraform.tfstate.backup" Enter
Type "rm -f /tmp/awx-demo-done" Enter
Type "alias clauded='claude --dangerously-skip-permissions'" Enter
Type "export PS1='claude ▸ '" Enter
Type "clear" Enter
Show

# --- animated intro (AGENT/PROVIDER logo, agent-first story) so viewers know
#     what they're about to watch before Claude Code takes over. ---
Type "demo/intro.sh" Enter
Sleep 14s
Type "clear" Enter

# --- open Claude Code: Opus 4.8 high effort, permissions skipped so the
#     session runs unattended. Sleep lets the TUI fully initialize before the
#     prompt is submitted. ---
Sleep 1s
Type "# Claude Code: Opus 4.8, high effort" Enter
Type `clauded --model claude-opus-4-8 --effort high` Enter
Sleep 5s

# --- human handoff: one subagent per contract for full parallel coverage.
#     The agent runs demo/done.sh at the end so Wait+Screen can fire. ---
Type "Use the agentprovider skill to build a fresh Red Hat Ansible AWX provider with terraform-provider-dynamic against live AWX, then prove it with terraform apply and confirm the action launched a real AWX job. Use /Users/simon.lynch/git/demo-awx-dynamic/docs/awx-api-to-aap-resources.md to determine which resources, data sources, and actions to implement — cover every item listed under 'agentprovider contracts in this repo' (16 contracts total). Spawn one concurrent Sonnet 4.6 medium-effort subagent per contract so all 16 are built in parallel. At the end output a markdown table with columns: Resource | Kind | AWX API | conform | completeness | proven — one row per contract. Create Terraform resources to execute a job action and workflow using the created resources, then run terraform apply to confirm the provider works and the job launches in AWX. Confirm no drift on a second apply. Show the run logs."
Sleep 1500ms
Enter

# --- Fixed window for the agent to finish. 16 parallel Sonnet 4.6 subagents
#     should complete well inside 30m; raise if a take consistently runs long. ---
Sleep 25m

Ctrl+C
Sleep 700ms
Ctrl+C
Sleep 1s
Type "clear" Enter
Type "demo/outro.sh" Enter
Sleep 16s
