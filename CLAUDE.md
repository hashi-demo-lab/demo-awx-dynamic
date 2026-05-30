# demo-awx-dynamic

agentprovider demo repo — builds and proves Terraform provider contracts for Red Hat Ansible AWX using terraform-provider-dynamic.

See [AGENTS.md](AGENTS.md) for skill, credentials, artifact layout, and the AWX API → resource mapping.

## Skill

Always load the agentprovider skill before doing any contract work:

```
use skill .agents/skills/agentprovider
```

## Build from scratch — do not reuse prior work

Every contract must be authored fresh using the agentprovider skill (`use skill .agents/skills/agentprovider`), driving `agentprovider introspect` and `agentprovider bootstrap` against the live AWX API. Do not copy, restore, or reference contracts, cassettes, or Terraform files from git history, prior commits, `/tmp`, or any other location. The working tree is wiped before each run — treat it as empty and build everything from live API responses only.

## Binaries

Both binaries are built from source by `demo/record-awx.sh` and placed on PATH. To build manually:

```bash
cd /Users/simon.lynch/git/research-dynamic-provider/terraform-provider-dynamic
go build -o /Users/simon.lynch/git/demo-awx-dynamic/agentprovider ./cli/agentprovider
go build -o /Users/simon.lynch/git/demo-awx-dynamic/terraform-provider-dynamic .
```

## Terraform dev override

```bash
printf 'provider_installation {\n  dev_overrides {\n    "hashicorp/dynamic" = "%s"\n  }\n  direct {}\n}\n' \
  "$PWD/demo/awx/tf/bin" > /tmp/awx-dev.tfrc
export TF_CLI_CONFIG_FILE=/tmp/awx-dev.tfrc
export AGENTPROVIDER_CONTRACTS=$PWD/.agentprovider/contracts
```

## Demo recording

```bash
demo/record-awx.sh                               # record v5 (default)
demo/record-awx.sh demo/test-agentprovider.tape  # isolated single-contract test
```

Requires: local AWX at `$AWX` (default `http://localhost:30080`), Claude Code auth, VHS, ffmpeg. The tape wipes all contracts and cassettes before each run — every take is a fresh build from scratch.
