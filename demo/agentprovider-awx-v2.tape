# agentprovider AWX demo v2 (VHS) — live Codex user experience.
# The outer tape prepares the local AWX/provider environment, then hands the work
# to a real Codex session. Codex uses the agentprovider skill to author and prove
# AWX contracts for organization, inventory, job template, and host resources,
# plus a Terraform action for launching an AWX job.
#
# Render manually with:
#   demo/record-awx.sh
# or update the recorder to point vhs at this v2 tape.
#
# Needs local AWX-on-Docker/kind, codex auth, and the demo-built agentprovider
# and terraform-provider-dynamic binaries.
Output demo/agentprovider-awx-v2.gif
Output demo/agentprovider-awx-v2.mp4

Set Shell bash
Set FontSize 18
Set Width 1500
Set Height 860
Set Padding 24
Set Theme "Catppuccin Mocha"
Set WindowBar Colorful
Set TypingSpeed 45ms

# --- setup (hidden): record-awx.sh has already built agentprovider and the
#     generic provider. Put them on PATH, configure local AWX credentials, point
#     Terraform at the freshly built provider binary, and keep the shell prompt
#     short for the recording. ---
Hide
Type "cd /Users/simon.lynch/git/research-dynamic-provider" Enter
Type "export PATH=$PWD/demo/bin:$PATH" Enter
Type "export AWX_PASSWORD=$(cat demo/awx/.admin_password)" Enter
Type "export AWX=${AWX:-http://localhost:30080}" Enter
Type "export AGENTPROVIDER_CONTRACTS=$PWD/.agentprovider/contracts" Enter
Type "sed 's#DEV_OVERRIDE_BIN_DIR#'$PWD'/demo/awx/tf/bin#' demo/awx/tf/dev.tfrc > /tmp/awx-dev.tfrc" Enter
Type "export TF_CLI_CONFIG_FILE=/tmp/awx-dev.tfrc" Enter
Type "source .env" Enter
Type "mkdir -p .agentprovider/contracts .agentprovider/cassettes" Enter
Type "rm -f .agentprovider/contracts/awx_*.yaml .agentprovider/cassettes/awx_*.cassette.yaml" Enter
Type "rm -rf examples/awx demo/awx/tf/.terraform demo/awx/tf/terraform.tfstate demo/awx/tf/terraform.tfstate.backup" Enter
Type "export PS1='codex ▸ '" Enter
Type "clear" Enter
Show

# --- open Codex on the fast low-effort model profile. Sleep lets the TUI fully
#     initialize before the prompt is submitted. ---
Sleep 1s
Type `codex --model gpt-5.5 -c 'model_reasoning_effort="medium"' --ask-for-approval never` Enter
Sleep 5s

# --- human handoff: Codex performs the bootstrap/record/conform/repair loop.
#     The request intentionally describes the desired provider surface, not the
#     low-level shell commands, so the demo shows the agentprovider authoring UX. ---
Type "I want to use the agentprovider skill to create a new AWX provider using terraform-provider-dynamic from scratch. Assume there are no pre-existing AWX contracts, cassettes, Terraform examples, or Terraform state to reuse. Do not restore or copy old AWX files; author fresh contracts under .agentprovider/contracts and fresh cassettes under .agentprovider/cassettes. I need resources for organization, inventory, job template, and hosts. I also want to use a Terraform action for job execution so Terraform can execute an AWX job. Use the local AWX credentials from the sourced .env file, but do not print or read out .env contents. Follow the standard agentprovider workflow with --allow-mutations, run agentprovider conform until each contract is proven, then create fresh Terraform code under examples/awx and apply it to validate. Keep credentials out of files and print PROVEN when the contracts conform and Terraform apply succeeds."
Sleep 1500ms
Enter

# --- Let Codex work. This is a real provider-authoring session with live AWX
#     mutations, conformance loops, and Terraform apply, so leave generous room.
#     Record once, inspect the render, and keep the good take. ---
Sleep 2s
Sleep 15m
