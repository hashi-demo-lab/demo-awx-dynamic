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

**Every command prints a compact JSON verdict and a `next:` hint — follow the
hints; they encode this loop.** For repeat passes over known paths, prefer
`agentprovider workflow <file|->` (one compact JSON summary; `--include-output` for
full detail). Ask the CLI for authoritative rules instead of reading Go source:
`agentprovider schema | invariants <c> | describe <field-path> | validate <c>`.
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
  Anti-pattern: hand-assembling standalone `completeness` + `conform --emit-proof`
  as your default — `prove` wraps them, so running them separately just doubles
  work. Use standalone `conform`/`completeness` only for focused repair detail.
- **Re-record only after changing a *replayed request*** (body, path,
  `conformance.example`, or `update_to`). Field classification and
  `ignore_server_fields` are diff-only — just re-run `prove`.

## Per-command notes

- **introspect** — read-only live field discovery; writes nothing. Use a
  **write-scoped** token: many DRF APIs only serve the `actions.POST` `OPTIONS`
  descriptor to a principal with add permission, and a read-only token silently
  degrades to `source: sample, confidence: reduced`. `--auth-env` takes an env-var
  *name* and is bearer-only. `--allow-private-host`/`--allow-insecure` for reviewed
  dev targets. Each high-confidence `--format json` row carries a ready-to-use
  `attribute` object — feed the JSON straight into `bootstrap --from-introspect`,
  then resolve only the `review_descriptor_metadata` rows by hand (FK ids →
  `type: number`; JSON/blob inputs → `type: string, default: ""`).
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
| Statuses | Every op declares `expect_status`; add observed async statuses only after review. |
| Update requests | `update.body` and `conformance.update_to` must carry the same request keys. |
| Field names | Remap Terraform meta-args with `field:`; mark every object/nested attr required/optional/computed. |
| Attribute shape | By omit behavior: rejects → `required`; null/absent → `optional`; stable scalar → `optional+default`; non-pinnable → `optional+computed`. |
| URL identities | Identity tokens used in URLs should be `type: string`; integer FK ids can stay numeric. |
| Actions | `dynamic_<type>_<verb>` comes from the action verb; by-id inputs must not share an API field with computed outputs. |

### Proving by contract kind

| Kind | Proof shape |
|---|---|
| Resource | CRUD invariants + floor `import_reconstructs` and `id_stable_across_update` for id-keyed read+update resources. |
| DataSource | `read_returns_expected`; example has read inputs + ≥1 real computed output. |
| Ephemeral | `ephemeral_open_renew_close`; open/renew/close modeled, computed outputs asserted. |
| Action-only | `action_returns_expected` + `state_matches_expect` (`not_null`) for server ids; no `create` lifecycle, no CRUD floor. |

Action-only contracts are `kind: Resource` in YAML but Terraform sees them as
Actions (`dynamic_<type>_<verb>`). Worked contracts: `references/contract-format.md`.

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
