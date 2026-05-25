#!/usr/bin/env bash
# Render the agentprovider AWX demo (VHS → gif + mp4).
# Builds the CLI to demo/bin, verifies AWX is reachable, then runs vhs.
#
#   demo/record-awx.sh                       # v3 tape, http://localhost:30080
#   demo/record-awx.sh demo/agentprovider-awx.tape   # render a specific tape
#   AWX=http://host:port demo/record-awx.sh
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD

# Which tape to render (default: the v3 Claude Code demo). The gif/mp4 names are
# derived from the tape's basename, matching each tape's own Output directives.
TAPE="${1:-demo/agentprovider-awx-v3.tape}"
if [ ! -f "$TAPE" ]; then
  echo "tape not found: $TAPE" >&2
  exit 1
fi
BASE="demo/$(basename "$TAPE" .tape)"

echo "==> building agentprovider → demo/bin/agentprovider"
( cd terraform-provider-dynamic && go build -o "$ROOT/demo/bin/agentprovider" ./cli/agentprovider )
export PATH="$ROOT/demo/bin:$PATH"

echo "==> building terraform-provider-dynamic → demo/awx/tf/bin/"
mkdir -p demo/awx/tf/bin
( cd terraform-provider-dynamic && go build -o "$ROOT/demo/awx/tf/bin/terraform-provider-dynamic" . )

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

echo "==> AWX up at $AWX; rendering $TAPE"
vhs "$TAPE"

# VHS's native mp4 export is unreliable here; transcode the gif → a clean,
# self-contained mp4 (even dimensions + yuv420p for broad player support).
echo "==> transcoding $BASE.mp4 from the gif"
ffmpeg -y -i "$BASE.gif" -movflags +faststart -pix_fmt yuv420p \
  -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libx264 -crf 20 \
  "$BASE.mp4"
echo "==> wrote $BASE.gif and $BASE.mp4"
