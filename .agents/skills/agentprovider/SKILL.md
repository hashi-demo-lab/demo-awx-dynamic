---
name: agentprovider
description: >-
  Author and prove an agentprovider YAML contract that turns an HTTP/REST API into
  a Terraform provider, data source, ephemeral resource, or custom action —
  config-driven, no hand-written Go. Use when someone wants Terraform to drive an
  HTTP API: an OpenAPI spec or REST endpoints made into a provider/resource/data
  source, a short-lived token that never hits state, a counter's up/down verbs, or
  an async 202-poll create. Also triggers on agentprovider,
  terraform-provider-dynamic, or `agentprovider bootstrap/introspect/record/conform/preflight`
  (including repair-hint questions). Drives the introspect/bootstrap →
  preflight → record → prove loop until the contract is proven against recorded
  responses. NOT for running an already-authored provider (docs/RUNNING.md),
  hand-writing a provider with terraform-plugin-framework, editing the engine
  internals, or debugging an existing third-party Terraform provider.
---

# Authoring an agentprovider contract

agentprovider turns a declarative YAML contract into a Terraform provider at
runtime — there is no per-API Go to write. Author one contract for a target API and
**prove it correct** against recorded responses. The contract is the unit of work;
the conformance verdict is the definition of done.

## The loop

```
introspect (when a live schema endpoint exists) → bootstrap (seed) → preflight → record (cassette) → prove --uplift → apply repair_hints / classify fields → re-run until overall_passed → terraform apply (runtime proof, `agentprovider hcl` emits the HCL) → generate (the end-state artifact: a standalone provider repo whose replay test must pass)
```

**Step 0 — one setup script, then never repeat a preamble.** Shell state does
not persist between commands, and re-typing env/source/export prefixes on
every call is the single biggest turn-waster measured in eval transcripts.
Write `setup.sh` ONCE (verify/rebuild the binary — stale installs silently
lack newer subcommands; never read Go source to discover CLI capabilities —
plus env sourcing and any exports), then start every subsequent command with
`source setup.sh && …`:

```bash
cat > setup.sh <<'SH'
if ! agentprovider prove -h >/dev/null 2>&1; then
  (cd terraform-provider-dynamic && go build -o /tmp/agentprovider ./cli/agentprovider)
  export PATH=/tmp:$PATH
fi
# source credentials / export API_BASE_URL etc. here, without printing values
SH
source setup.sh
```

**Every command prints a compact JSON verdict and a `next:` hint — follow the
hints; they encode this loop.** Once a contract is seeded and its paths are
known, do NOT hand-run validate/preflight/record/prove as separate commands —
bundle them with `agentprovider workflow <file|->` (one compact JSON verdict;
ready-to-adapt file under "Bundle the proof loop" below; `--include-output` for
full detail).

**HARD RULE: never open engine Go source (`internal/`, `cli/`) while authoring.**
Every authoring question has a CLI answer — map your uncertainty to a command:

| Unsure about… | Ask |
|---|---|
| What subcommands or flags exist | `agentprovider help`, `agentprovider help <cmd>` |
| Contract schema shape / one block | `agentprovider schema --path <block>` (e.g. `lifecycle.create`) |
| What a field means or accepts | `agentprovider describe <field-path>` (`describe --list` for all paths) |
| Which invariants a contract needs | `agentprovider invariants <contract.yaml>` |
| Whether a draft loads | `agentprovider validate <contract.yaml>` |

If the CLI genuinely can't answer, check `references/cli-loop.md` before
touching Go — a needed source read is a skill gap to report, not a workaround.
Exact flags and stable JSON shapes: `references/cli-loop.md`.

**HARD RULE: independent commands and tool calls go in ONE turn.** Setup
ceremony, multi-file scaffold writes, and independent per-contract record/prove
runs are all batchable — issue them together. Only dependent pairs stay
sequential: a `set` repair must land before `workflow --resume-from` re-enters.

**HARD RULE: contract edits go through `agentprovider set`.** Raw file edits
are only for shapes `set` cannot express. The echoed per-path diff is
authoritative — never read the contract back after a successful `set`.

Three rules that govern the whole loop:

- **Seed before you `record`.** `record` replays an *existing* contract, so seed
  first. Default seed is `bootstrap`; when a live schema endpoint exists,
  `bootstrap --from-introspect` is the fast path — it builds create/update bodies
  from settable fields only, avoiding the loop's biggest sink (pruning a giant
  `--response` draft). Hand-authoring is a narrow exception: say so, and `validate`
  that it loads under strict decoding before recording (quote `${id}` in flow-map
  `path:` values — unquoted breaks YAML).
- **`agentprovider prove --uplift` is THE terminal gate.** It runs the completeness
  gate *and* `conform --mutation-check --emit-proof` in one pass and writes the
  proof sidecar; `--uplift` auto-routes server-owned fields to reach 100%.
  Never run standalone `conform` or `completeness` as a first pass — `prove`
  wraps both, so a separate run is pure duplicate work. The one sanctioned
  trigger for standalone `conform` is: `prove` has **already failed** AND its
  aggregate output lacks the repair detail you need. Return to `prove` for the
  verdict afterwards — a green standalone `conform` is not the terminal gate.
- **Re-record only after changing a *replayed request*** (body, path,
  `conformance.example`, or `update_to`). Field classification and
  `ignore_server_fields` are diff-only — just re-run `prove`.

### Bundle the proof loop: `workflow` is the default, not an option

Hand-running `validate` → `preflight` → `record` → `prove` as four separate
commands — parsing four JSON results per contract — is the expensive path.
After introspect/bootstrap seed the drafts, write **one workflow file for ALL
contracts** (a `contracts:` list runs the same step pipeline per contract; a
failed contract does not stop the others, so one invocation returns every
verdict and repair hint). Adapt this directly:

```yaml
base_url_env: API_BASE_URL   # keeps the live URL out of the file
uplift: true
steps:
  - name: preflight              # strict-loads the contract; a separate validate step is redundant
    stage: record
  - name: record
    allow_mutations: true        # drop for read-only data sources
    if_cassette_missing: true    # repair re-runs skip record automatically
  - name: prove
  - generate                     # proven contracts emit standalone repos
out_dir: .agentprovider/generated/{name}
contracts:
  - contract: contracts/<type-a>.yaml
    cassette: .agentprovider/cassettes/<type-a>.cassette.yaml
  - contract: contracts/<type-b>.yaml
    cassette: .agentprovider/cassettes/<type-b>.cassette.yaml
```

(For a single contract, top-level `contract:`/`cassette:` instead of the list
still works; per-entry `allow_mutations`/`uplift`/`metadata` override the
file-level defaults.)

On a failed verdict, repair and re-enter — don't re-run everything: the failing
step's full `output` carries `repair_patches` (feed them to
`agentprovider set <contract> --patch -`), and the failed contract entry carries
a `resume_from` token plus a ready-to-run `next_action`, so the repair lands via `set` and
`workflow <file> --resume-from <token>` re-enters the same file at the failed
step. Never fall back to driving record/prove/generate per contract by hand. Put
`if_cassette_missing: true` on the record step and `repair: true` at file level
from the start (the `--workflow-out` file does both): first run records,
diff-only repair re-runs skip record with no live calls, machine-applicable
patches auto-apply, and a replay miss (changed replayed request / stale
cassette) auto-re-records once and re-proves — no `force: true` edits needed. The runner
executes built-in steps only — `introspect` and `bootstrap` still happen first,
outside the file. Full step options and per-step overrides:
`references/cli-loop.md` (`workflow` section).

## Per-command notes

Exact flags, JSON shapes, and worked detail live in `references/cli-loop.md` —
load it when a command surprises you. The load-bearing rules:

| Command | The rule that saves a loop |
|---|---|
| introspect | Endpoint is a POSITIONAL arg (`introspect /api/v2/ --base-url <origin>`), never part of `--base-url`. Collection key for `--get`: `results` (workflow's is `contracts`). Leading-slash full path + origin-only `--base-url`. One command: `--expand --grep <t1>[,<t2>]` on the API root. Write-scoped token or OPTIONS silently degrades to `sample/reduced`. Heed `fk_candidate` rows — writable FKs now seed as settable optional inputs (already in the body); `review_fks` review means confirming requiredness and supplying fixture ids, not reclassifying. (`bootstrap --all` surfaces `review_fks`/`review_fields` per contract; untranscribed structured fields still 400 the first record if unreviewed.) |
| bootstrap | `--from-introspect` is the seed path (`--all --workflow-out` for everything at once) and works for sample/reduced-confidence introspect too — fields seed with `--response`-style conservative roles (identity computed, the rest optional inputs to review); `--openapi --list --grep` to find anchors in specs without reading them. The draft is a starting point to repair. |
| preflight | Advisory readiness check; strict-loads the contract (separate validate step is redundant). |
| record | One live pass → replayable cassette. `--allow-mutations` for CRUD; real credentials go to `base_url`, so record against reviewed staging. Follow `next_action`/`set_expect_status`/`model_delete_less`/`gone_when_candidates` suggestions (the last flags a tombstone read-after-delete — model `lifecycle.read.gone_when` before prove); back off only on 5xx. |
| prove | THE terminal gate (`--uplift`); stdout pure JSON. Standalone `conform` only AFTER a failed prove lacking detail. |
| hcl / generate | `hcl` emits main.tf+dev.tfrc (don't hand-write); `generate` (workflow step) emits the standalone repo — `go mod tidy` once, then its replay test is the end-state proof. Re-running generate with unchanged inputs skips as ok (PROVENANCE hash match); changed inputs need `-force`. |

## Classify fields — the one test

*Does the API accept this field as a create/update input?* **Yes** → model it in
`schema.attributes` as `optional` (`+computed` only for a non-pinnable server
default; prefer `default: <literal>`). **Pure server output** (timestamps,
`related`, `summary_fields`, `url`, `detail`, counters, `*_role`) →
`ignore_server_fields`. **FK/reference ids and behavior toggles (`enable_*`,
`*_enabled`, the whole `ask_*` / `*_on_launch` family) ARE settable** — modeling a
few while sweeping dozens of settable knobs into `ignore_server_fields` to hit 100%
is **green-washing**, and `prove --metadata <schema>` refuses it
(`green-washing refusal: ignored N settable inputs`). A read-only DataSource /
Ephemeral has no settable inputs (route the envelope to `ignore_server_fields`,
model useful outputs as `computed`); an action is low-by-design on completeness —
judge it by `action_returns_expected`, not a percent. Full rubric, blind-spot, and
server-envelope starter set: `references/completeness-and-greenwashing.md`.

You reach 100% on a verbose API by routing the **server-owned envelope** into
`ignore_server_fields` (a diff-only change, no re-record), **not** by sweeping
settable inputs into it. The proof sidecar is `<type>.proven.json` (the `.yaml` is
replaced, not appended) and must carry `mutation_status: "passed_targeted"`.

## Get these right up front (loop-burners)

Keep these in working memory; open `references/gotchas.md` /
`references/repair-hints.md` only when a rule needs detail or a symptom needs mapping.

| Rule | Fast fix |
|---|---|
| Private or plaintext dev target | Set `allow_private_host` / `allow_insecure` in `connection` after review. |
| Auth shape | Put `auth` under `connection`; basic-auth keys are `username` and `password`. |
| Runtime base URL | Use `${env.VAR}` or provider config; `conform` does not prove `base_url`. |
| Paths | Use `${...}`, never `{...}`; keep `base_url` as origin, full paths in ops. |
| Statuses | Every op declares `expect_status`; add observed async statuses only after review. Some APIs run DELETE (or update) async — a delete returning 202 is *success*, not an error: declare `expect_status: [202]` up front. Add the op's `async` block **only when the 202 body/headers carry something to poll** (a job id or status URL); a body-less 202 is not pollable-async — just accept the status, and if reads tombstone the deleted object (e.g. a `pending_deletion` flag), model it with `lifecycle.read.gone_when` instead. |
| Credential-name false positives | A settable enum/toggle whose name merely matches a credential pattern (`authorization_grant_type`, `skip_authorization`) must NOT be `sensitive` — redaction makes echo invariants unprovable. Declare `not_secret: true` after reviewing the value is genuinely not a secret (mutually exclusive with `sensitive`); introspect/bootstrap seed it automatically for bool attrs and server-enumerated choice fields. A one-time write-only server secret returned only on create (e.g. an OAuth client_secret) goes to `ignore_server_fields`, not `computed+sensitive`. |
| Write-only create secrets | A required-on-create secret the server never returns (a user password, a one-time token) is modeled `write_only: true` (requires required|optional; never computed/default/carry_on_read; sets unsupported). The value lives only in config and request bodies — never plan or state — so live apply succeeds; echo invariants automatically skip it. Introspect seeds it for write-only descriptors. Needs Terraform >= 1.11. |
| Nested sensitive sub-fields | A secret sub-field of a `type: object` attribute whose server read-back differs from the input (a password echoed as a masked sentinel) is modeled `write_only: true` on the sub-field — the value never enters plan/state, so the masked read-back cannot fail apply. |
| Delete-less APIs | A DELETE 405 (or no DELETE in metadata) means the API never deletes this resource: omit `lifecycle.delete` entirely (destroy = forget), drop `delete_then_read_404` from invariants, and use a fresh example name on any record retry — the prior object cannot be cleaned up. |
| Update requests | `update.body` and `conformance.update_to` must carry the same request keys. |
| Field names | Remap Terraform meta-args with `field:`; mark every object/nested attr required/optional/computed. |
| Attribute shape | By omit behavior: rejects → `required`; null/absent → `optional`; stable scalar → `optional+default`; non-pinnable → `optional+computed`. |
| URL identities | Identity tokens used in URLs should be `type: string`; integer FK ids can stay numeric. |
| Actions | `dynamic_<type>_<verb>` comes from the action verb; by-id inputs must not share an API field with computed outputs. After `record`, fill output proof from the cassette: stable values (`status`, `name`) → `conformance.example`; server-assigned id-shaped values → `conformance.expect.<attr>: {not_null: true}`. |

### Proving by contract kind

| Kind | Proof shape |
|---|---|
| Resource | CRUD invariants + floor `import_reconstructs` and `id_stable_across_update` for id-keyed read+update resources. |
| DataSource | `read_returns_expected`; example has read inputs + ≥1 real computed output. |
| Ephemeral | `ephemeral_open_renew_close`; open/renew/close modeled, computed outputs asserted. |
| Action-only | `action_returns_expected` + `state_matches_expect` (`not_null`) for server ids; no `create` lifecycle, no CRUD floor. |

Action-only contracts are `kind: Resource` in YAML but Terraform sees them as
Actions (`dynamic_<type>_<verb>`). Worked contracts: `references/contract-format.md`.
For a specific contract's concrete floor and missing entries, run
`agentprovider invariants <contract.yaml>` — the CLI, not engine Go or test
source, is the authority on proof shape.

## Two outcomes you must distinguish

- **Contract invalid / capability inexpressible** — the contract won't load, or the
  API needs something the format lacks. Do **not** delete invariants or weaken the
  contract to pass (that green-washes an unproven contract). If the format genuinely
  can't express it, say so and stop — a real engine gap to report.
- **Valid but invariant failed** — a fixable mismatch (wrong status, missing remap,
  perpetual diff). Apply the repair hint and re-run. The normal loop.

## Terraform proof

After `prove` passes, run a live apply. Do NOT hand-write the HCL:
`agentprovider hcl <contract.yaml>` emits `main.tf` (from
`conformance.example`) plus `dev.tfrc`, and its `next` hints carry the exact
build/apply commands — including the two traps (the binary must be named
`terraform-provider-dynamic` inside the override dir, and
`AGENTPROVIDER_CONTRACTS` must point at the contract dir). The mechanical
mapping (`create` → `resource "dynamic_<type>"`, DataSource → `data`,
Ephemeral → `ephemeral`, action-only → `action "dynamic_<type>_<verb>"`)
remains for reference and multi-resource graphs; when wiring a cross-resource
FK whose types differ (string URL identity → numeric FK), convert in HCL:
`tonumber(parent.id)`. Invoke actions from a sibling
resource's `action_trigger` (avoids target self-cycles), wire FKs through computed
ids, keep credentials in env/provider config. Full HCL: `references/terraform-usage.md`.

## Security (the engine can't enforce these)

Prefer `auth.type: header|basic|oauth2` over `query` (query auth logs the secret in
the URL). Mark every credential-bearing attribute `sensitive: true` — the redactor
scrubs transport but **cannot reach Terraform attribute values**. Source secrets
from `${env.VAR}` / `auth.env` / provider config, never a literal in the YAML.

## Reference files (load on demand, not up front)

- `references/cli-loop.md` — exact flags + stable JSON shapes for every command.
- `references/contract-format.md` — every contract block and field, with worked kinds.
- `references/repair-hints.md` — standard invariant set + repair-hint catalog.
- `references/completeness-and-greenwashing.md` — field-classification rubric, the
  green-washing blind-spot and `--metadata` gate, server-envelope set.
- `references/gotchas.md` — the loop-burner catalog in worked detail.
- `references/terraform-usage.md` — HCL surface, `action_trigger`, FK wiring, a
  worked graph for the live `apply` proof.

When editing this skill or its evals, run
`sh .agents/skills/agentprovider/scripts/check_quality.sh` before calling it done.

## Done means (in this order)

1. Fresh/changed contracts with a live schema endpoint used `introspect` first, or the summary says why none existed.
2. Every fresh/changed contract was seeded with `bootstrap` (or the hand-author exception is stated and the draft confirmed to load).
3. Contracts recorded with `record` against the intended target.
4. `agentprovider prove <c> <cassette>` passes for every resource/data-source contract (or the equivalent `completeness` + mutation-proof is shown); important `missing` fields are modeled or judged out of scope — settable inputs as attributes, not swept into `ignore_server_fields`.
5. The Terraform example that consumes the contracts applies against the runtime.
6. The cassette is redacted/reviewed; credentials come from env/provider config.

Only report `PROVEN` after all applicable steps are complete.
