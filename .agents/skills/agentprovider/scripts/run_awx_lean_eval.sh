#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../../../.." && pwd)

fail() {
  printf 'agentprovider AWX lean eval failed: %s\n' "$1" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

require_env() {
  eval "value=\${$1:-}"
  [ -n "$value" ] || fail "missing required environment variable: $1"
}

wait_for_awx() {
  attempt=1
  while [ "$attempt" -le 20 ]; do
    status=$(curl -sS -o /dev/null -w "%{http_code}" "$AWX/api/v2/ping/" 2>/dev/null || true)
    [ "$status" = "200" ] && return 0
    sleep 1
    attempt=$((attempt + 1))
  done
  fail "AWX target not reachable at $AWX after 20s"
}

require_cmd curl
require_cmd date
require_cmd go
require_cmd jq
require_cmd ruby
require_cmd terraform

if [ -f "$repo_root/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$repo_root/.env"
  set +a
fi

require_env AWX
require_env AWX_USERNAME
require_env AWX_PASSWORD
wait_for_awx

RUN_TAG=${RUN_TAG:-$(date +%Y%m%d%H%M%S)}
WORK=${WORK:-/private/tmp/agentprovider-awx-lean-${RUN_TAG}}
ORG_NAME=apeval-${RUN_TAG}-lean-org
ORG_UPDATE_NAME=apeval-${RUN_TAG}-lean-org-updated
TF_ORG_NAME=apeval-${RUN_TAG}-lean-tf-org
JT_NAME=apeval-${RUN_TAG}-lean-job-template
JT_UPDATE_NAME=apeval-${RUN_TAG}-lean-job-template-updated
TF_JT_NAME=apeval-${RUN_TAG}-lean-tf-job-template

PROJECT_ID=${PROJECT_ID:-6}
INVENTORY_ID=${INVENTORY_ID:-1}
PLAYBOOK=${PLAYBOOK:-hello_world.yml}

mkdir -p "$WORK/bin" "$WORK/contracts" "$WORK/cassettes" "$WORK/tf/contracts" "$WORK/tf/provider-bin"

TOKEN_FILE=$WORK/awx_token
TOKEN_ID_FILE=$WORK/awx_token_id
METRICS_FILE=$WORK/metrics.json
START_SECONDS=$(date +%s)
APPLIED=0

cleanup() {
  if [ "$APPLIED" = "1" ] && [ -f "$WORK/tf/terraform.tfstate" ]; then
    (
      export AWX_TOKEN=$(cat "$TOKEN_FILE" 2>/dev/null || true)
      export API_BASE_URL="$AWX"
      export AGENTPROVIDER_CONTRACTS="$WORK/tf/contracts"
      export TF_CLI_CONFIG_FILE="$WORK/tf/dev.tfrc"
      terraform -chdir="$WORK/tf" destroy -auto-approve -input=false > "$WORK/tf/destroy.cleanup.log" 2>&1 || true
    )
  fi

  if [ -f "$TOKEN_ID_FILE" ]; then
    token_id=$(cat "$TOKEN_ID_FILE" 2>/dev/null || true)
    if [ -n "$token_id" ] && [ "$token_id" != "null" ]; then
      curl -sS -u "$AWX_USERNAME:$AWX_PASSWORD" -H 'Content-Type: application/json' \
        -X DELETE "$AWX/api/v2/tokens/$token_id/" -o "$WORK/token-delete-body.txt" \
        -w "%{http_code}" > "$WORK/token-delete-status.txt" || true
    fi
  fi

  rm -f "$TOKEN_FILE" "$TOKEN_ID_FILE" "$WORK/token-response.json"
}
trap cleanup EXIT INT TERM

printf 'agentprovider AWX lean eval workspace: %s\n' "$WORK"

curl -sS -u "$AWX_USERNAME:$AWX_PASSWORD" -H 'Content-Type: application/json' \
  -X POST "$AWX/api/v2/tokens/" \
  -d '{"description":"agentprovider lean eval"}' > "$WORK/token-response.json"
jq -r '.token' "$WORK/token-response.json" > "$TOKEN_FILE"
jq -r '.id' "$WORK/token-response.json" > "$TOKEN_ID_FILE"
[ "$(cat "$TOKEN_FILE")" != "null" ] || fail "AWX token creation returned null"

(
  cd "$repo_root/terraform-provider-dynamic"
  GOCACHE=${GOCACHE:-/private/tmp/rdp-gocache} \
    GOMODCACHE=${GOMODCACHE:-/private/tmp/rdp-gomodcache} \
    go build -o "$WORK/bin/agentprovider" ./cli/agentprovider
  GOCACHE=${GOCACHE:-/private/tmp/rdp-gocache} \
    GOMODCACHE=${GOMODCACHE:-/private/tmp/rdp-gomodcache} \
    go build -o "$WORK/tf/provider-bin/terraform-provider-dynamic" .
)

export AWX_TOKEN=$(cat "$TOKEN_FILE")
export API_BASE_URL="$AWX"

"$WORK/bin/agentprovider" introspect /api/v2/organizations/ \
  --base-url "$AWX" --auth-env AWX_TOKEN --allow-insecure --allow-private-host \
  --format json > "$WORK/organization.introspect.json"
"$WORK/bin/agentprovider" introspect /api/v2/job_templates/ \
  --base-url "$AWX" --auth-env AWX_TOKEN --allow-insecure --allow-private-host \
  --format json > "$WORK/job_template.introspect.json"

"$WORK/bin/agentprovider" bootstrap --from-introspect "$WORK/organization.introspect.json" \
  --type lean_organization --out "$WORK/contracts/lean_organization.yaml" > "$WORK/bootstrap-organization.json"
"$WORK/bin/agentprovider" bootstrap --from-introspect "$WORK/job_template.introspect.json" \
  --type lean_job_template --out "$WORK/contracts/lean_job_template.yaml" > "$WORK/bootstrap-job-template.json"

ORG_NAME=$ORG_NAME ORG_UPDATE_NAME=$ORG_UPDATE_NAME ruby -ryaml -e '
path = ARGV.fetch(0)
doc = YAML.load_file(path)
doc["connection"]["allow_insecure"] = true
doc["connection"]["allow_private_host"] = true
doc["conformance"]["example"]["name"] = ENV.fetch("ORG_NAME")
doc["conformance"]["example"]["description"] = ENV.fetch("ORG_NAME")
doc["conformance"]["update_to"]["name"] = ENV.fetch("ORG_UPDATE_NAME")
doc["conformance"]["update_to"]["description"] = ENV.fetch("ORG_UPDATE_NAME")
doc["schema"]["attributes"].delete("default_environment")
doc["ignore_server_fields"] = %w[
  created custom_virtualenv default_environment modified related summary_fields type url
]
File.write(path, YAML.dump(doc))
' "$WORK/contracts/lean_organization.yaml"

JT_NAME=$JT_NAME JT_UPDATE_NAME=$JT_UPDATE_NAME PROJECT_ID=$PROJECT_ID INVENTORY_ID=$INVENTORY_ID PLAYBOOK=$PLAYBOOK ruby -ryaml -e '
def add_once(list, value)
  list << value unless list.include?(value)
end

path = ARGV.fetch(0)
doc = YAML.load_file(path)
doc["connection"]["allow_insecure"] = true
doc["connection"]["allow_private_host"] = true

example = doc["conformance"]["example"]
update_to = doc["conformance"]["update_to"]
example["name"] = ENV.fetch("JT_NAME")
update_to["name"] = ENV.fetch("JT_UPDATE_NAME")
{
  "project" => ENV.fetch("PROJECT_ID").to_i,
  "inventory" => ENV.fetch("INVENTORY_ID").to_i,
  "playbook" => ENV.fetch("PLAYBOOK")
}.each do |key, value|
  example[key] = value
  update_to[key] = value
end

%w[create update].each do |op|
  body = doc["lifecycle"][op]["body"]
  add_once(body, "project")
  add_once(body, "inventory")
end

attrs = doc["schema"]["attributes"]
attrs["project"].delete("computed")
attrs["project"]["optional"] = true
attrs["project"]["default"] = ENV.fetch("PROJECT_ID").to_i
attrs["inventory"].delete("computed")
attrs["inventory"]["optional"] = true
attrs["inventory"]["default"] = ENV.fetch("INVENTORY_ID").to_i
attrs["playbook"]["default"] = ENV.fetch("PLAYBOOK")
%w[execution_environment webhook_credential webhook_service].each do |field|
  attrs.delete(field)
end

doc["ignore_server_fields"] = %w[
  created custom_virtualenv execution_environment last_job_failed last_job_run
  modified next_job_run organization related status summary_fields type url
  webhook_credential webhook_service
]
File.write(path, YAML.dump(doc))
' "$WORK/contracts/lean_job_template.yaml"

cat > "$WORK/workflow-organization.yaml" <<EOF
contract: $WORK/contracts/lean_organization.yaml
cassette: $WORK/cassettes/lean_organization.cassette.yaml
base_url_env: API_BASE_URL
uplift: true
steps:
  - validate
  - name: record
    suggest: true
    allow_mutations: true
    force: true
  - prove
EOF

cat > "$WORK/workflow-job-template.yaml" <<EOF
contract: $WORK/contracts/lean_job_template.yaml
cassette: $WORK/cassettes/lean_job_template.cassette.yaml
base_url_env: API_BASE_URL
uplift: true
steps:
  - validate
  - name: record
    suggest: true
    allow_mutations: true
    force: true
  - prove
EOF

"$WORK/bin/agentprovider" workflow "$WORK/workflow-organization.yaml" > "$WORK/workflow-organization.json"
"$WORK/bin/agentprovider" workflow "$WORK/workflow-job-template.yaml" > "$WORK/workflow-job-template.json"

jq '.steps[0].summary' "$WORK/workflow-organization.json" > "$WORK/validate-organization.json"
jq '.steps[0].summary' "$WORK/workflow-job-template.json" > "$WORK/validate-job-template.json"
jq '.steps[1].summary' "$WORK/workflow-organization.json" > "$WORK/record-organization.json"
jq '.steps[1].summary' "$WORK/workflow-job-template.json" > "$WORK/record-job-template.json"
jq '.steps[2].summary' "$WORK/workflow-organization.json" > "$WORK/proof-organization.json"
jq '.steps[2].summary' "$WORK/workflow-job-template.json" > "$WORK/proof-job-template.json"
jq '{overall_passed: .conform_passed}' "$WORK/proof-organization.json" > "$WORK/conform-organization.json"
jq '{overall_passed: .conform_passed}' "$WORK/proof-job-template.json" > "$WORK/conform-job-template.json"
jq '{passed: .completeness_passed}' "$WORK/proof-organization.json" > "$WORK/completeness-organization.json"
jq '{passed: .completeness_passed}' "$WORK/proof-job-template.json" > "$WORK/completeness-job-template.json"

# Generate a standalone Terraform provider scaffold from each freshly-recorded
# contract and prove it through its own generated replay acceptance test
# (terraform-plugin-testing). Because the cassette was just recorded against live
# AWX with the current engine, the generated provider must reproduce the same
# request shapes the engine recorded. This is the `generate` arm of the eval.
GENERATE_OK=1
for name in organization job_template; do
  gen="$WORK/generated/lean_${name}"
  if ! "$WORK/bin/agentprovider" generate \
    -contract "$WORK/contracts/lean_${name}.yaml" \
    -cassette "$WORK/cassettes/lean_${name}.cassette.yaml" \
    -out "$gen" -force > "$WORK/generate-${name}.json" 2> "$WORK/generate-${name}.err"; then
    GENERATE_OK=0
    printf 'generate failed for lean_%s (see %s)\n' "$name" "$WORK/generate-${name}.err" >&2
    continue
  fi
  if ! (
    cd "$gen"
    GOCACHE=${GOCACHE:-/private/tmp/rdp-gocache} \
      GOMODCACHE=${GOMODCACHE:-/private/tmp/rdp-gomodcache} go mod tidy
    TF_ACC=1 GOCACHE=${GOCACHE:-/private/tmp/rdp-gocache} \
      GOMODCACHE=${GOMODCACHE:-/private/tmp/rdp-gomodcache} \
      go test ./internal/provider/... -run Replay -count=1
  ) > "$WORK/generated-gotest-${name}.log" 2>&1; then
    GENERATE_OK=0
    printf 'generated provider go test failed for lean_%s (see %s)\n' "$name" "$WORK/generated-gotest-${name}.log" >&2
  fi
done
[ "$GENERATE_OK" = "1" ] || fail "generate arm failed (generate or generated replay go test)"
printf 'generate arm passed: standalone scaffolds generated and replay-tested for organization, job_template\n'

cp "$WORK/contracts/lean_organization.yaml" "$WORK/contracts/lean_organization.proven.json" \
  "$WORK/contracts/lean_job_template.yaml" "$WORK/contracts/lean_job_template.proven.json" \
  "$WORK/tf/contracts/"

cat > "$WORK/tf/dev.tfrc" <<EOF
provider_installation {
  dev_overrides {
    "hashi-demo-lab/dynamic" = "$WORK/tf/provider-bin"
  }

  direct {}
}
EOF

cat > "$WORK/tf/main.tf" <<EOF
terraform {
  required_providers {
    dynamic = {
      source = "hashi-demo-lab/dynamic"
    }
  }
}

provider "dynamic" {
  base_url = "$AWX"
}

resource "dynamic_lean_organization" "runtime" {
  name        = "$TF_ORG_NAME"
  description = "$TF_ORG_NAME"
  max_hosts   = 1
}

resource "dynamic_lean_job_template" "runtime" {
  name      = "$TF_JT_NAME"
  project   = $PROJECT_ID
  inventory = $INVENTORY_ID
  playbook  = "$PLAYBOOK"
}

output "organization_id" {
  value = dynamic_lean_organization.runtime.id
}

output "job_template_id" {
  value = dynamic_lean_job_template.runtime.id
}
EOF

export AGENTPROVIDER_CONTRACTS="$WORK/tf/contracts"
export TF_CLI_CONFIG_FILE="$WORK/tf/dev.tfrc"
terraform -chdir="$WORK/tf" init -input=false > "$WORK/tf/init.log"
terraform -chdir="$WORK/tf" apply -auto-approve -input=false > "$WORK/tf/apply.log"
APPLIED=1
terraform -chdir="$WORK/tf" plan -detailed-exitcode -input=false > "$WORK/tf/plan-noop.log"
plan_code=$?
[ "$plan_code" -eq 0 ] || fail "second terraform plan was not a no-op; exit $plan_code"

curl -sS -u "$AWX_USERNAME:$AWX_PASSWORD" "$AWX/api/v2/organizations/?name=$TF_ORG_NAME" > "$WORK/tf/api-org-before-destroy.json"
curl -sS -u "$AWX_USERNAME:$AWX_PASSWORD" "$AWX/api/v2/job_templates/?name=$TF_JT_NAME" > "$WORK/tf/api-job-template-before-destroy.json"
[ "$(jq -r '.count' "$WORK/tf/api-org-before-destroy.json")" = "1" ] || fail "expected one Terraform organization before destroy"
[ "$(jq -r '.count' "$WORK/tf/api-job-template-before-destroy.json")" = "1" ] || fail "expected one Terraform job template before destroy"

terraform -chdir="$WORK/tf" destroy -auto-approve -input=false > "$WORK/tf/destroy.log"
APPLIED=0

curl -sS -u "$AWX_USERNAME:$AWX_PASSWORD" "$AWX/api/v2/organizations/?name__startswith=apeval-${RUN_TAG}-lean-" > "$WORK/cleanup-organizations.json"
curl -sS -u "$AWX_USERNAME:$AWX_PASSWORD" "$AWX/api/v2/job_templates/?name__startswith=apeval-${RUN_TAG}-lean-" > "$WORK/cleanup-job-templates.json"
org_leftovers=$(jq -r '.count' "$WORK/cleanup-organizations.json")
jt_leftovers=$(jq -r '.count' "$WORK/cleanup-job-templates.json")
[ "$org_leftovers" = "0" ] || fail "organization cleanup left $org_leftovers object(s)"
[ "$jt_leftovers" = "0" ] || fail "job-template cleanup left $jt_leftovers object(s)"

END_SECONDS=$(date +%s)
WALL_SECONDS=$((END_SECONDS - START_SECONDS))

jq -n \
  --arg run_tag "$RUN_TAG" \
  --arg work "$WORK" \
  --arg metrics_file "$METRICS_FILE" \
  --arg skill_version "$(git -C "$repo_root" rev-parse --short HEAD 2>/dev/null || echo unknown)" \
  --arg cli_version "$(git -C "$repo_root" rev-parse --short HEAD 2>/dev/null || echo unknown)" \
  --argjson wall_seconds "$WALL_SECONDS" \
  --argjson org_conform "$(jq '.overall_passed' "$WORK/conform-organization.json")" \
  --argjson jt_conform "$(jq '.overall_passed' "$WORK/conform-job-template.json")" \
  --argjson org_complete "$(jq '.passed' "$WORK/completeness-organization.json")" \
  --argjson jt_complete "$(jq '.passed' "$WORK/completeness-job-template.json")" \
  --argjson org_proof "$(jq '.overall_passed' "$WORK/proof-organization.json")" \
  --argjson jt_proof "$(jq '.overall_passed' "$WORK/proof-job-template.json")" \
  '{
    eval: "awx-lean",
    run_tag: $run_tag,
    workspace: $work,
    metrics_file_path: $metrics_file,
    skill_version: $skill_version,
    cli_version: $cli_version,
    changed_lever: "cli+skill+eval",
    token_total: null,
    token_note: "shell harness cannot capture agent-token telemetry",
    wall_seconds: $wall_seconds,
    record_iterations: {organization: 1, job_template: 1},
    conform_iterations: {organization: 1, job_template: 1},
    rerecord_count: 0,
    source_reads: 0,
    manual_scaffold_edits: 0,
    reviewed_contract_edits: [
      "reviewed local/private host flags",
      "unique example names",
      "job_template fixture inputs",
      "response-owned ignore_server_fields"
    ],
    proof_quality: {
      organization: {conform: $org_conform, completeness: $org_complete, mutation_proof: $org_proof},
      job_template: {conform: $jt_conform, completeness: $jt_complete, mutation_proof: $jt_proof},
      terraform_apply: true,
      terraform_noop_plan: true,
      terraform_destroy: true,
      generate_replay: true
    },
    cleanup_status: "verified_clean"
  }' > "$METRICS_FILE"

jq '.' "$METRICS_FILE"
