# agentprovider — AWX demo (VHS)
# Agent-first Terraform provider generation: like agent-browser, but for providers.
# An agent authors, PROVES, and RUNS two AWX capabilities against live AWX-on-Docker:
#   (1) an inventory CRUD resource, (2) job execution as a custom ACTION,
#   (3) a real `terraform apply` driving the generic provider.
# Render with: demo/record-awx.sh  (builds CLI + provider, checks AWX, runs vhs).

Output demo/agentprovider-awx.gif

Set Shell "bash"
Set FontSize 15
Set Width 1360
Set Height 820
Set Padding 22
Set TypingSpeed 30ms

# --- setup (off camera) ---
Hide
Type "cd /Users/simon.lynch/git/research-dynamic-provider"
Enter
Type "export PATH=$PWD/demo/bin:$PATH"
Enter
Type "export AWX_PASSWORD=$(cat demo/awx/.admin_password)"
Enter
Type "export AWX=${AWX:-http://localhost:30080}"
Enter
Type "export AGENTPROVIDER_CONTRACTS=$PWD/.agentprovider/contracts"
Enter
Type "sed 's#DEV_OVERRIDE_BIN_DIR#'$PWD'/demo/awx/tf/bin#' demo/awx/tf/dev.tfrc > /tmp/awx-dev.tfrc"
Enter
Type "export TF_CLI_CONFIG_FILE=/tmp/awx-dev.tfrc"
Enter
Type "clear"
Enter
Show

# --- animated intro (AGENT/PROVIDER logo, agent-first story) ---
Type "demo/intro.sh"
Enter
Sleep 14s
Type "clear"
Enter

# =====================================================================
# (1) inventory — a CRUD resource
# =====================================================================
Type "#  (1) an AWX inventory — a CRUD resource, declared as YAML"
Enter
Enter
Sleep 800ms
Type "demo/show.sh yaml .agentprovider/contracts/awx_inventory.yaml 19,33"
Enter
Sleep 3s
Enter
Type "#  record one live pass against AWX  →  a byte-accurate cassette"
Enter
Sleep 500ms
Type "agentprovider record .agentprovider/contracts/awx_inventory.yaml --base-url $AWX --allow-mutations --force --out .agentprovider/cassettes/awx_inventory.cassette.yaml"
Enter
Sleep 6s
Enter
Type "#  conform — replay the cassette and check the declared invariants"
Enter
Sleep 500ms
Type "demo/conform-summary.sh .agentprovider/contracts/awx_inventory.yaml .agentprovider/cassettes/awx_inventory.cassette.yaml"
Enter
Sleep 4s
Type "clear"
Enter

# =====================================================================
# (2) job execution — as an ACTION, not a resource
# =====================================================================
Type "#  (2) AWX job execution — modeled as an ACTION, not a resource"
Enter
Enter
Sleep 800ms
Type "demo/show.sh yaml .agentprovider/contracts/awx_job.yaml 37,41"
Enter
Sleep 3s
Enter
Type "#  launch a job template against live AWX, then prove the action"
Enter
Sleep 500ms
Type "agentprovider record .agentprovider/contracts/awx_job.yaml --base-url $AWX --allow-mutations --force --out .agentprovider/cassettes/awx_job.cassette.yaml"
Enter
Sleep 5s
Enter
Type "demo/conform-summary.sh .agentprovider/contracts/awx_job.yaml .agentprovider/cassettes/awx_job.cassette.yaml"
Enter
Sleep 4s
Type "clear"
Enter

# =====================================================================
# (3) provider execution — a real terraform apply
# =====================================================================
Type "#  (3) the GENERIC provider RUNS the contracts — a real terraform apply"
Enter
Enter
Sleep 800ms
Type "demo/show.sh terraform demo/awx/tf/main.tf 11,31"
Enter
Sleep 5s
Enter
Type "#  apply: create the AWX inventory, and the action_trigger launches a job"
Enter
Sleep 500ms
Type "terraform -chdir=demo/awx/tf apply -auto-approve"
Enter
Sleep 9s
Enter
Type "#  inventory resource + job-launch action — authored, proven, and applied to live AWX."
Enter
Sleep 3s
Type "clear"
Enter

# --- closing card (recap + THE END) ---
Type "demo/outro.sh"
Enter
Sleep 7s
