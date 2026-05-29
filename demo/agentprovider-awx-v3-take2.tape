# agentprovider AWX demo v3 take 2 (VHS) — live Codex/GPT user experience.
# Codex uses the repo-local agentprovider skill to drive the
# agentprovider CLI against live AWX. The demo now asks the agent to keep the CLI
# surface visible: show each agentprovider command it runs and leave the raw
# output on screen instead of hiding it behind summaries or helper scripts.
#
# Scope: fresh contracts for organization, inventory, job template, and host
# resources; a data source; job-launch and workflow-job-launch actions; then a
# real Terraform init/apply/plan using terraform-provider-dynamic.
#
# Render manually with:
#   demo/record-awx.sh
# or update the recorder to point vhs at this v3 tape.
#
# Needs local AWX-on-Docker/kind, Codex auth, and the repo-local
# agentprovider and terraform-provider-dynamic binaries.
Output demo/agentprovider-awx-v3-take2.gif

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
#     binary, and keep the shell prompt short for the recording. ---
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
Type "export PS1='gpt-fast ▸ '" Enter
Type "clear" Enter
Show

# --- animated intro (AGENT/PROVIDER logo, agent-first story) so viewers know
#     what they're about to watch before Codex/GPT takes over. ---
Type "demo/intro.sh" Enter
Sleep 14s
Type "clear" Enter

# --- open Codex on GPT-5.5 Fast mode. `service_tier="priority"` is the
#     catalog-backed Fast tier; `model_reasoning_effort="low"` keeps the run
#     light. Sleep lets the TUI fully initialize before the prompt is submitted. ---
Sleep 1s
Type "# GPT-5.5 Fast mode: service_tier=priority, reasoning=low" Enter
Type `codex --model gpt-5.5 --enable fast_mode -c 'service_tier="priority"' -c 'model_reasoning_effort="low"' --ask-for-approval never` Enter
Sleep 5s

# --- human handoff: Codex/GPT performs the full CLI-driven authoring loop.
#     The prompt explicitly asks the agent to show the command line UX: help,
#     bootstrap/introspection, preflight, record, conform, completeness,
#     proof emission, and Terraform validation commands with their output. ---
Type "Use the repo-local agentprovider skill to build a fresh AWX provider with terraform-provider-dynamic from scratch. Assume there are no existing AWX contracts, cassettes, Terraform examples, or Terraform state to reuse; do not restore or copy old AWX files. Author fresh contracts under .agentprovider/contracts and fresh cassettes under .agentprovider/cassettes. Cover all three contract kinds: resources with full CRUD for organization, inventory, job template, and host; a data source that looks up an existing AWX object by id and exposes computed fields; and two Terraform actions: awx_job_launch for POST /api/v2/job_templates/${id}/launch/ and aap_workflow_job_launch for POST /api/v2/workflow_job_templates/${id}/launch/. Use local AWX via ${env.AWX} with credentials from the sourced .env (${env.AWX_USERNAME}/${env.AWX_PASSWORD}), but do not print or read .env contents and keep credentials out of files. Important for the recording: show the agentprovider CLI clearly. Before or as you run each step, type the actual agentprovider command in the visible terminal and leave its output visible; do not hide CLI output behind scripts or only summarize it. Start by showing the CLI surface with agentprovider help and relevant help for bootstrap, schema, invariants, validate, describe, preflight, record, conform, and completeness. Then run the standard workflow visibly: bootstrap or seed drafts, schema/invariants/validate/describe introspection, preflight, record with --allow-mutations --suggest, conform until every contract passes, completeness for each resource and data source, conform --mutation-check --emit-proof, create fresh Terraform under examples/awx using the resources, data source, and both actions, terraform init, terraform apply -auto-approve, cat the Terraform code, and run a second terraform plan to prove no-op idempotence. If a by-id data source or action needs an existing AWX object, create or identify a fixture first. If the workflow job template is missing, create one or target an existing one before recording the workflow action. Verify the job and workflow actions via the AWX API, scan contracts/cassettes/HCL for credential leaks, summarize what was implemented and the elapsed time, and print PROVEN only after all contracts conform, completeness passes for resources/data source, Terraform apply succeeds, both actions execute, the second plan is no-op, and no credential values are present in artifacts."
Sleep 1500ms
Enter

# --- Let Codex/GPT work. This is a real provider-authoring session with live
#     AWX mutations, conformance loops, and Terraform apply, so leave generous
#     room. Record once, inspect the render, and keep the good take. ---
Sleep 2s
Sleep 18m
