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
introspect (when a live schema endpoint exists) → bootstrap (seed) → preflight → record (cassette) → prove --uplift → apply repair_hints / classify fields → re-run until overall_passed → terraform apply (runtime proof)
```

**Step 0 — verify the binary before anything else.** Installed copies go stale
(a symlink into another checkout can silently lack newer subcommands such as
`prove`). Rebuild if needed — never read Go source to discover what the CLI
supports:

```bash
if ! agentprovider prove -h >/dev/null 2>&1; then
  (cd terraform-provider-dynamic && go build -o /tmp/agentprovider ./cli/agentprovider)
  export PATH=/tmp:$PATH
fi
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
After introspect/bootstrap seed the draft, write one workflow file per contract
and run `agentprovider workflow <file>` for one compact JSON verdict. Adapt
this directly (only the two artifact paths change per contract):

```yaml
contract: contracts/<type>.yaml
cassette: .agentprovider/cassettes/<type>.cassette.yaml
base_url_env: API_BASE_URL   # keeps the live URL out of the file
uplift: true
steps:
  - validate
  - name: preflight
    stage: record
  - name: record
    allow_mutations: true    # drop for read-only data sources
  - name: prove
```

On a failed verdict, apply the repair hints and re-run the same file (add
`force: true` on the record step only when you changed a replayed request —
diff-only fixes don't need it, and the record step is skippable once the
cassette is good: a `prove`-only re-run is just `steps: [prove]`). The runner
executes built-in steps only — `introspect` and `bootstrap` still happen first,
outside the file. Full step options and per-step overrides:
`references/cli-loop.md` (`workflow` section).

## Per-command notes

- **introspect** — read-only live field discovery; writes nothing. The endpoint
  positional is a **leading-slash full path including the API version prefix**,
  joined to an **origin-only** `--base-url` — e.g.
  `agentprovider introspect /api/v1/widgets/ --base-url https://api.example.com --auth-env TOKEN`.
  A 301/404 whose failing URL shows the host glued directly to the path with no
  slash between them means the endpoint/base_url join is wrong — fix the
  shapes above, not the credentials. Use a
  **write-scoped** token: many DRF APIs only serve the `actions.POST` `OPTIONS`
  descriptor to a principal with add permission, and a read-only token silently
  degrades to `source: sample, confidence: reduced`. `--auth-env` takes an env-var
  *name* and is bearer-only. `--allow-private-host`/`--allow-insecure` for reviewed
  dev targets. Output is JSON by default; each high-confidence row carries a
  ready-to-use `attribute` object — pipe it straight into `bootstrap --from-introspect`,
  then resolve only the `review_descriptor_metadata` rows by hand (FK ids →
  `type: number`; JSON/blob inputs → `type: string, default: ""`). Schema/`OPTIONS`
  descriptors routinely **omit required-ness on FK/reference inputs** (a parent or
  owner id may be required to create but is not flagged required), so
  `--from-introspect` can leave a required FK out of the create body. Before the
  first record, ask whether the object can exist without each FK — if not, model
  it as `required` and put it in `conformance.example`; and a create **400 naming
  a missing field means model that FK as required**, not that the API is broken.
- **bootstrap** — seed from `--openapi` (`--operation` or `--path`+`--method`),
  `--response` (a sample JSON body), or `--from-introspect`. `--kind` is
  `resource` (default) | `datasource` | `ephemeral` | `action`; `--action <verb>`
  names an action verb. `--alias param=attr` links a path param to an attribute;
  `--ignore <name>` drops pagination/noise. The draft is a starting point to
  *repair*: bootstrap fills what the spec states and leaves quirks (non-conventional
  `_id`, empty PUT, 202 poll, `auth`, `async`, `pagination`, `refresh_after`,
  `ignore_server_fields`, ephemeral renew/close, an action's real expected output)
  for you. Ephemeral/action drafts are valid but **not-yet-conforming** (placeholder
  paths/outputs) — repair before `conform`. Narrative on every block:
  `references/contract-format.md`.
- **preflight** — `agentprovider preflight <c> --stage record --base-url "$URL"`
  reports blockers/warnings/expectations and the exact next command. Advisory; does
  not mutate the contract.
- **record** — one live pass captures byte-accurate responses into a replayable
  cassette. Add `--allow-mutations` to issue create/update/delete; `--suggest` for
  `ignore_server_fields`/unmodeled-field hints (advisory, never an auto-edit; weigh
  lightly on read-only data sources). Every id you reference must already exist
  live — create a throwaway fixture for a by-id data source or action. Recording
  sends **real credentials** to `base_url`: record against a reviewed staging
  `--base-url`, never an unread production URL (the engine rejects private/loopback
  hosts unless `allow_private_host`). Cassettes are auto-redacted, but review before
  commit. If `record` reports an async status outside `expect_status`, or refuses an
  existing cassette, follow its `next_action`/`set_expect_status` suggestion and
  re-record with `--force` — don't fork a parallel cassette. Back off only on 5xx /
  transport timeouts (bounded, jittered); 4xx and replay misses are repair paths.
- **prove** — offline replay; positional `<contract> <cassette>` only (no
  `--base-url`; don't pass introspect JSON to `--metadata`). **stdout is pure JSON,
  human status lines go to stderr** — parse `prove … 2>/dev/null | parser`. On
  `overall_passed: false`, apply the top `conform.repair_hints[]` and re-run. A
  contract must declare `conformance.invariants` — the harness fails closed on zero
  checks. Invariant set + repair-hint catalog (symptom → fix → why):
  `references/repair-hints.md`.

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
| Statuses | Every op declares `expect_status`; add observed async statuses only after review. Some APIs run DELETE (or update) async — a delete returning 202 is *success*, not an error: declare `expect_status: [202]` plus the op's `async` block up front, don't burn a record discovering it. |
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

After `prove` passes, run a live apply. Mapping is mechanical: `create` →
`resource "dynamic_<type>"`, DataSource → `data`, Ephemeral → `ephemeral`,
action-only → `action "dynamic_<type>_<verb>"`. Invoke actions from a sibling
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
