Output demo/test-agentprovider.gif

Set Shell bash
Set Framerate 12
Set FontSize 18
Set Width 1500
Set Height 860
Set Padding 24
Set Theme "Catppuccin Mocha"
Set WindowBar Colorful
Set TypingSpeed 27ms

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
Type "rm -rf .agentprovider/contracts .agentprovider/cassettes .agentprovider/schemas .agentprovider/metadata" Enter
Type "mkdir -p .agentprovider/contracts .agentprovider/cassettes" Enter
Type "rm -rf examples/awx demo/awx/tf/.terraform demo/awx/tf/terraform.tfstate demo/awx/tf/terraform.tfstate.backup" Enter
Type "rm -f /tmp/awx-demo-done" Enter
Type "alias clauded='claude --dangerously-skip-permissions'" Enter
Type "export PS1='claude ▸ '" Enter
Type "clear" Enter
Show

Sleep 1s
Type "# Claude Code: Opus 4.8, high effort — single contract test" Enter
Type `clauded --model claude-opus-4-8 --effort high` Enter
Sleep 5s

Type "Use the agentprovider skill to build and prove a single AWX contract: the aap_organization resource at /api/v2/organizations/. Use a single Haiku 4.5 subagent to do the work. When proven, run terraform apply against live AWX to confirm it works. As your absolute final action run bash demo/done.sh as a standalone Bash tool call — do not chain it with any other command"
Sleep 1500ms
Enter

Sleep 10m

Ctrl+C
Sleep 700ms
Ctrl+C
Sleep 1s
Type "clear" Enter
