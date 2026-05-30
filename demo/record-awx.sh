#!/usr/bin/env bash
# Render the agentprovider AWX demo (VHS → mp4 directly).
# Builds the CLI/provider from source, verifies AWX is reachable, then runs vhs.
#
#   demo/record-awx.sh                       # v3 take 2 tape, http://localhost:30080
#   demo/record-awx.sh demo/agentprovider-awx.tape   # render a specific tape
#   AWX=http://host:port demo/record-awx.sh
#   AGENTPROVIDER_SOURCE=/path/to/terraform-provider-dynamic demo/record-awx.sh
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD

# Which tape to render. Tapes output mp4 directly (VHS-native h264) — gif
# palettegen chokes on long (12+ min) captures, so we skip it entirely.
TAPE="${1:-demo/agentprovider-awx-v5.tape}"
if [ ! -f "$TAPE" ]; then
  echo "tape not found: $TAPE" >&2
  exit 1
fi
BASE="demo/$(basename "$TAPE" .tape)"

# Refuse to start if a VHS render is already running — two concurrent renders
# write the same output path and corrupt each other (one ends up 0 bytes).
if pgrep -x vhs >/dev/null 2>&1; then
  echo "a vhs render is already running — kill it first (pgrep -x vhs)." >&2
  echo "concurrent renders collide on the output path and produce an empty file." >&2
  exit 1
fi

SOURCE="${AGENTPROVIDER_SOURCE:-/Users/simon.lynch/git/research-dynamic-provider/terraform-provider-dynamic}"
if [ ! -f "$SOURCE/go.mod" ]; then
  echo "agentprovider source not found at $SOURCE" >&2
  echo "Set AGENTPROVIDER_SOURCE to the terraform-provider-dynamic source directory." >&2
  exit 1
fi
export GOCACHE="${GOCACHE:-/private/tmp/demo-awx-gocache}"

echo "==> building agentprovider → demo/bin/agentprovider"
mkdir -p demo/bin
( cd "$SOURCE" && go build -o "$ROOT/demo/bin/agentprovider" ./cli/agentprovider )
cp demo/bin/agentprovider agentprovider
export PATH="$ROOT/demo/bin:$PATH"

echo "==> building terraform-provider-dynamic → demo/awx/tf/bin/"
mkdir -p demo/awx/tf/bin
( cd "$SOURCE" && go build -o "$ROOT/demo/awx/tf/bin/terraform-provider-dynamic" . )
cp demo/awx/tf/bin/terraform-provider-dynamic terraform-provider-dynamic

if [ ! -f demo/awx/.admin_password ]; then
  echo "missing demo/awx/.admin_password (the local AWX admin credential)" >&2
  exit 1
fi
export AWX_PASSWORD="$(cat demo/awx/.admin_password)"
export AWX="${AWX:-http://localhost:30080}"
export AGENTPROVIDER_CONTRACTS="$ROOT/.agentprovider/contracts"

code=$(curl -s -o /dev/null -w '%{http_code}' "$AWX/api/v2/ping/" || true)
if [ "$code" != "200" ]; then
  echo "AWX not reachable at $AWX (ping returned $code)." >&2
  echo "Start it first (kind + awx-operator); see demo/awx/." >&2
  exit 1
fi

# Fresh start so section (3)'s `terraform apply` is a real create every render:
# drop local TF state and delete any leftover demo inventory from a prior run
# (AWX inventory names are unique per org, so a stale one would block create).
echo "==> pre-clean: terraform state + stray demo inventory"
rm -f demo/awx/tf/terraform.tfstate demo/awx/tf/terraform.tfstate.backup
stale=$(curl -s -u "admin:$AWX_PASSWORD" "$AWX/api/v2/inventories/?name=agentprovider-tf-demo" \
  | python3 -c 'import sys,json; print("\n".join(str(o["id"]) for o in json.load(sys.stdin).get("results",[])))' 2>/dev/null || true)
for id in $stale; do
  curl -s -u "admin:$AWX_PASSWORD" -X DELETE "$AWX/api/v2/inventories/$id/" -o /dev/null
  echo "   deleted stale inventory $id"
done

echo "==> AWX up at $AWX; rendering $TAPE → $BASE.mp4"
vhs "$TAPE"
echo "==> wrote $BASE.mp4"
