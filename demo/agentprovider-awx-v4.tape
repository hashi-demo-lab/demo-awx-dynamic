# agentprovider AWX demo v4 (VHS) — live Claude Code user experience.
# Same shape as v3 take 2, but the agent driving the work is Claude Code
# (Opus 4.8) instead of Codex/GPT-5.5. Claude Code uses the repo-local
# agentprovider skill to drive the agentprovider CLI against live AWX. The demo
# asks the agent to keep the CLI surface visible: show each agentprovider
# command it runs and leave the raw output on screen instead of hiding it behind
# summaries or helper scripts.
#
# Scope: fresh contracts for organization, inventory, job template, and host
# resources; a data source; job-launch and workflow-job-launch actions; then a
# real Terraform init/apply/plan using terraform-provider-dynamic.
#
# Render manually with:
#   demo/record-awx.sh demo/agentprovider-awx-v4.tape
#
# Needs local AWX-on-Docker/kind, Claude Code auth, and the repo-local
# agentprovider and terraform-provider-dynamic binaries.
Output demo/agentprovider-awx-v4.gif

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
Type "mkdir -p .agentprovider/contracts .agentprovider/cassettes" Enter
Type "rm -f .agentprovider/contracts/awx_*.yaml .agentprovider/cassettes/awx_*.cassette.yaml" Enter
Type "rm -rf examples/awx demo/awx/tf/.terraform demo/awx/tf/terraform.tfstate demo/awx/tf/terraform.tfstate.backup" Enter
Type "alias clauded='claude --dangerously-skip-permissions'" Enter
Type "export PS1='claude ▸ '" Enter
Type "clear" Enter
Show

# --- animated intro (AGENT/PROVIDER logo, agent-first story) so viewers know
#     what they're about to watch before Claude Code takes over. ---
Type "demo/intro.sh" Enter
Sleep 14s
Type "clear" Enter

# --- open Claude Code: Opus 4.8 on medium effort, permissions skipped so the
#     session runs unattended. Sleep lets the TUI fully initialize before the
#     prompt is submitted. ---
Sleep 1s
Type "# Claude Code: Opus 4.8, medium effort" Enter
Type `clauded --model claude-opus-4-8 --effort medium` Enter
Sleep 5s

# --- human handoff: minimal prompt. Internal tech demo — we intentionally want
#     Claude to run the agentprovider CLI and leave its raw output on screen. ---
Type "Use the repo-local agentprovider skill to build a fresh Red Hat Ansible AWX provider with terraform-provider-dynamic against live AWX, then prove it with terraform apply. Show the completeness/classification gate for each contract. Run each agentprovider command in the visible terminal and leave its raw output on screen — don't hide it behind scripts or summaries."
Sleep 1500ms
Enter

# --- Let Claude Code work. Fixed Sleep, NOT a dynamic Wait: the agent runs
#     inside the Claude Code TUI, which renders tool output in collapsed widgets
#     rather than plain scrolling text, so VHS `Wait+Screen` cannot reliably match
#     terraform's "Apply complete!" — and a Wait timeout discards the ENTIRE
#     recording. A sized Sleep always yields a gif. Observed full run ~16m41s, so
#     18m captures a complete session and leaves it idle on the final frame. If
#     the agent needs longer on a given take, raise this and re-record. ---
Sleep 2s
Sleep 15m

# --- exit the Claude TUI back to the shell, then play the closing card. The
#     agent leaves us at Claude's idle input prompt; Ctrl+C twice quits it (the
#     first press arms "press again to exit"). Then run demo/outro.sh — the green
#     recap, the figlet "THE END" banner, and the tagline. The Sleep covers the
#     outro's ~14s of animated printf/sleep beats so the card plays in full. ---
Ctrl+C
Sleep 700ms
Ctrl+C
Sleep 1s
Type "clear" Enter
Type "demo/outro.sh" Enter
Sleep 16s
