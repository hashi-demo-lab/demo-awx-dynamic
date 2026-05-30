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
  preflight → record → conform → completeness/proof loop until the contract is
  proven against recorded responses. NOT
  for running an already-authored provider (docs/RUNNING.md), hand-writing a
  provider with terraform-plugin-framework, editing the engine internals, or
  debugging an existing third-party Terraform provider.
---

# Authoring an agentprovider contract

agentprovider builds a Terraform provider by **interpreting a declarative YAML
contract at runtime** — there is no per-API Go to write. Author one contract for
a target API and **prove it correct** against recorded responses, using the
`agentprovider` CLI's authoring seams. The contract is the unit of work; the
conformance verdict is the definition of done.

The mandatory loop, in order. When a live schema-bearing endpoint exists, run
`introspect` before seeding the draft; otherwise start at `bootstrap` and note
why live discovery was unavailable.

```
introspect (live field discovery, no writes, when available)  →  bootstrap (seed)  →  schema/invariants/describe/validate (authoring introspection)  →  preflight  →  record (capture a cassette)  →  conform (machine verdict)  →  apply repair_hints  →  re-run until overall_passed  →  completeness/classification (coverage + field repair gate)  →  conform --mutation-check --emit-proof  →  Terraform apply (runtime proof)
```

**A seeded draft must exist before you `record`** — `record` replays an existing
contract, so seed first. The default seed is `agentprovider bootstrap` (from an
OpenAPI spec or a tiny sample response); when introspect gave you the settable
surface, the blessed fast path is to bootstrap a thin scaffold and lift the schema
from introspect (see §1's efficiency note). _Narrow exception:_ if you hand-author
the whole draft, (a) state that and why, and (b) confirm it loads under strict
decoding before recording — hand-written YAML is where load errors creep in (e.g. an
unquoted `${id}` in a flow-mapping `path:` breaks YAML; quote such paths).

`conform` returning `overall_passed` is the correctness loop; `completeness` is a
mandatory follow-on gate (model enough of the surface, classify missing fields). For
Terraform-provider tasks, don't report `PROVEN` until all contracts conform,
completeness has been checked for each, and the Terraform example has applied.
Input can be an OpenAPI spec, a sample JSON response, or a base URL + your knowledge
of the API. To only *run* an existing provider, see `docs/RUNNING.md`, not this skill.

## The loop in detail

### 1. Discover live settable fields with `agentprovider introspect`

Run `introspect` before authoring or bootstrapping when the API can describe its
create/update surface live (for example, a DRF endpoint with `OPTIONS` metadata),
or when you only have a sample endpoint and need a reduced-confidence field map
to review. It is read-only and writes no contract, cassette, metadata file, or
proof.

```bash
agentprovider introspect /api/v2/widgets/ --base-url "$BASE_URL" --auth-env AWX_TOKEN
agentprovider introspect /api/v2/widgets/ --base-url "$BASE_URL" --format json
```

Add `--allow-private-host` for a reviewed local/dev host and `--allow-insecure` for
credentialed `http://`. `--auth-env` takes an env-var **name** and is **bearer-only**
— for a basic-auth API (AWX), mint a token (`POST /api/v2/tokens/`) and point
`--auth-env` at it. Full flags: `references/cli-loop.md`.

**Use a token with *write* scope.** Many DRF APIs (AWX/AAP) only expose the
`actions.POST` descriptor on `OPTIONS` to a principal with *add* permission; a
read-only token silently degrades introspect to `source: sample, confidence: reduced`
(every field `unknown`, no copyable `attribute`). A write-scoped token returns
`source: options, confidence: high`. If you see `confidence: reduced` against an API
you know serves `OPTIONS`, re-mint with write scope before authoring.

**Efficiency — build the schema FROM introspect, don't re-derive it from a verbose
response.** Each high-confidence `--format json` field carries a ready-to-paste
`attribute` object already encoding the right shape (`required`,
`optional`+`default:<lit>`, `optional`+`computed`). Assemble `schema.attributes` by
**lifting those snippets directly**. On a 40+-field resource the by-hand rewrite of a
full `--response` draft is the single biggest token/time sink in the loop, and
introspect has already done that classification — so the fast path is: lift the
high-confidence `attribute`s → resolve only the `review_descriptor_metadata` rows by
hand (FK ids → settable `type: number`; JSON blobs like `extra_vars`/`variables` →
`type: string`, `default: ""`) → seed the lifecycle/connection scaffold + a tiny
sample for the response shape. This **is** the seeded draft — running `bootstrap`
with `--response` (a tiny sample) for the scaffold and then replacing its schema with
the lifted introspect attributes satisfies the bootstrap step; if you assemble the
draft by hand instead, say so and confirm it loads under `validate` before recording
(the narrow exception). Don't seed a giant `--response` draft and prune it when the
settable surface is already in hand.

**Two traps that turn the fast path into a slow one — both cost re-records, the most
expensive thing in the loop, so get them right before the first `record`:** (1)
introspect's type for a **choice/enum** field can be wrong — e.g. an integer choice
rendered as `string`, or marked `optional+computed` when it is really a defaulted
scalar. Sanity-check any `review_descriptor_metadata` or enum-looking field against
the OPTIONS `choices`/`type` before lifting (a numeric choice → `type: number`,
`default: <int>`). (2) **An `optional+computed` field the server defaults is still
sent in the request body, so it MUST appear in `conformance.example` (and `update_to`)
with the server's value** — leave it unpinned and the replayed body won't match the
cassette, forcing a re-record loop. When in doubt, pin defaulted scalars as
`optional: true, default: <lit>` rather than `optional+computed` (plan-known, and no
example-pinning needed). These two account for nearly all the re-record churn on a
verbose resource.

### 2. Seed a draft with `agentprovider bootstrap` — REQUIRED DRAFT STEP

**Always run this for a new or changed contract after live discovery when
available. Do not hand-author from scratch to skip `bootstrap`** (see the narrow
exception in the loop note above).

Turn whatever the user has into a first-draft contract. The draft is a starting
point to *repair*, not a finished contract — bootstrap fills in what the spec
states and leaves the quirks (the `_id` field, the empty PUT, the 202 poll) for
you.

```bash
# from an OpenAPI v3 spec (pick the resource anchor by operationId or path+method)
agentprovider bootstrap --openapi spec.yaml --operation createWidget --out contracts/widget.yaml
agentprovider bootstrap --openapi spec.yaml --path /widgets --method post --out contracts/widget.yaml

# from a single example response (resource or data source)
agentprovider bootstrap --response sample.json --type widget --kind resource --out contracts/widget.yaml
cat sample.json | agentprovider bootstrap --response - --type widget --kind datasource

# ephemeral (open/renew/close) and action (actions block) kinds
agentprovider bootstrap --openapi spec.yaml --operation login --kind ephemeral --out contracts/auth_token.yaml
agentprovider bootstrap --openapi spec.yaml --operation rotateKey --kind action --action rotate --out contracts/key.yaml

# override the path-param→attribute link, and drop pagination/noise fields
agentprovider bootstrap --openapi spec.yaml --path /pets/{petId} --method get --alias petId=id --ignore page --ignore limit
```

`--kind` is `resource` (default), `datasource`, `ephemeral`, or `action`;
`--action <verb>` names the verb for action kinds (only valid with `--kind action`).

From an OpenAPI spec the importer also marks credential fields `sensitive: true`,
carries non-sensitive string/bool `default`s (secrets are never written), and
auto-detects the identity attribute for a single-path-param by-id read
(`/pets/{petId}` → `${id}`). `--alias <param>=<attribute>` forces that link;
`--ignore <name>` drops pagination/noise (OpenAPI importer only — full flags in
`references/cli-loop.md`). A `--response` seed mirrors the *whole* example
faithfully and has no pruning, so on a verbose API (mostly `related`/`summary_fields`/
timestamps) **rewrite it down to the practitioner fields** — but per the efficiency
note above, when introspect gave you the settable surface, prefer lifting those
`attribute`s over rewriting a giant draft. The ephemeral and action kinds emit valid
but **not-yet-conforming** drafts (placeholder `renew`/`close` paths; placeholder
`conformance.example` outputs) — repair them before `conform` (`references/repair-hints.md`).

Then read the draft and fill the gaps, asking the CLI for authoritative rules rather
than reading Go source: `agentprovider schema` (the JSON Schema for the whole
contract-file format — distinct from the contract's own `schema.attributes` block),
`invariants <contract>`, `describe <field-path>`, and `validate <contract>`. Semantic
checks (pagination, credential sensitivity, conformance coverage) come from `validate`
/ `conform`. Flags and JSON shapes: `references/cli-loop.md`.

Use `references/contract-format.md` as narrative context. Common things
bootstrap can't infer: `identity.response_field` for a genuinely non-conventional
id (the common single-path-param by-id case is auto-detected; see above),
`refresh_after` (empty write responses), `ignore_server_fields` (server
timestamps), `auth`, `async`, `pagination`, `carry_on_read`/`normalize`,
ephemeral `renew`/`close` paths, and an action's real expected output value.

### 3. Preflight, then record a cassette with `agentprovider record`

Before recording, run:

```bash
agentprovider preflight contracts/widget.yaml --stage record --base-url "$BASE_URL"
```

Preflight reports blockers, warnings, expectations, and exact next commands. It
is advisory unless you choose to use it; it does not mutate the contract.

One live pass captures byte-accurate responses into a replayable cassette and
(with `--suggest`) proposes refinements such as `ignore_server_fields`
candidates, unmodeled fields, and field-level probe/repair suggestions.

```bash
agentprovider record contracts/widget.yaml --base-url https://api.example.com --suggest \
  --out .agentprovider/cassettes/widget.cassette.yaml
```

- For **resources**, add `--allow-mutations` only when you intend the recorder to
  issue create/update/delete against the target. Without it, only read-side /
  non-mutating calls are captured.
- **`record` hits the live API, so every id you reference must already exist there.**
  A `kind: DataSource` that looks up an object by id, and a by-id action whose path
  interpolates `${...}_id`, both need a real target object at record time — there is
  nothing to read or act on otherwise. If one doesn't exist yet, create a throwaway
  fixture (a quick API POST, or apply the sibling resource first) and record against
  its id.
- **`--suggest` is resource-tuned** — its `unmodeled_fields` /
  `ignore_server_fields` suggestions target a create/update surface, so weigh them
  lightly on a read-only data source and ignore any that don't fit the kind.
- **The "conformance.example pins X but the live run observed … will fail conform
  on re-record" stale-pin warning now compares against the *create-time*
  observation** (not the post-update one), so a field you deliberately change in
  `update_to` **no longer trips it** — keep the create value in `example` and the
  updated value in `update_to` as normal. If the warning *does* fire now, it is
  real: the pinned **computed output** genuinely diverged from the create-time
  response between runs (a server-assigned / volatile value — an id, a timestamp,
  a token). That is the one case where you **should** follow the suggestion and
  move the field to `conformance.expect.<f>: {not_null: true}` (proven by
  `state_matches_expect`) rather than pinning a value that won't reproduce. Pin
  only stable computed values in `example`; never pin a volatile/id-shaped one.
- **Security — recording sends real credentials to `base_url`.** For a freshly
  bootstrapped, unreviewed contract, record against a **user-controlled staging
  `--base-url`**, never an embedded production URL you haven't read. The engine
  rejects `base_url`/`token_url` that resolve to private/loopback/metadata hosts
  unless `allow_private_host` is set. Review a bootstrapped contract's URLs before
  pointing real credentials at them.
- Recorded cassettes are redacted (auth headers, query secrets, OAuth2 tokens,
  `client_secret`) before they hit disk, but **review a new cassette before
  committing** anyway. Redaction is conservative substring matching, so a short or
  common credential *value* (e.g. a username like `admin`) can show as a "redaction
  hit" against unrelated field-name text — that is over-matching, not a leak. Check
  that the real secret (the password/token) is absent; don't be alarmed by an
  incidental match.

### 4. Get a machine verdict with `agentprovider conform`

```bash
agentprovider conform contracts/widget.yaml .agentprovider/cassettes/widget.cassette.yaml
```

`conform` emits JSON on stdout **by default** (pass `--format text` for the concise
human verdict; `--json` is still accepted as an alias). **stdout is pure JSON;
human status lines go to stderr** — including the `mutation check: targeted
invariants bite N/M` banner under `--mutation-check`. So parse **stdout alone**
(`conform … 2>/dev/null | your-json-parser`); never capture `2>&1` and then wonder
why the JSON won't decode, and don't switch to `--format text` just to dodge a
"non-JSON preamble" that is actually on stderr. (`record`'s advisory warnings are
*also* surfaced inside the JSON `warnings[]` array, so a stdout-only reader still
sees them.) The JSON is stable:
`{contract, overall_passed, results[], repair_hints[], summary}`. Each failing
result carries `expected`, `actual`, `contract_path`, and `suggested_fix`;
`repair_hints` ranks unique fixes in failure order. Loop:

1. If `overall_passed` is true — done.
2. Otherwise apply the top `repair_hint` (see `references/repair-hints.md` for what
   each one means and *why*), re-run `conform`, repeat.

A contract must **declare the invariants it wants** under `conformance.invariants`
— the harness fails closed on a contract with zero checks (a green run with no
invariants is not a pass). Start from the standard set in
`references/repair-hints.md`.

### 5. Check completeness with `agentprovider completeness`

This step is mandatory after `conform` passes and before any final Terraform
runtime proof. Run it for every freshly authored or changed contract. If
completeness reports important missing fields, model them or deliberately explain
why they are out of scope before proceeding. Do not treat a green `conform` result
alone as sufficient proof.

`conform` proves the contract is *correct*; it does not prove it is *complete*. A
contract can pass every invariant while modeling only a handful of an endpoint's
fields. After it conforms, measure how much of the API surface you actually model:

```bash
# offline: diff against the fields recorded in the cassette (JSON by default)
agentprovider completeness contracts/widget.yaml .agentprovider/cassettes/widget.cassette.yaml
agentprovider completeness contracts/widget.yaml .agentprovider/cassettes/widget.cassette.yaml --openapi spec.yaml --operation createWidget --format text
# dynamic: diff against what the live API returns right now
agentprovider completeness contracts/widget.yaml --base-url https://api.example.com --min-completeness 90
```

It reports `completeness_percent`, `missing` (API returns them, no attribute models
them), `extra` (modeled but unseen — usually fine), plus `fields[]` classifications,
`suggestions[]`, and — for resources — a **`settable_coverage`** ratio and
**`ignored_settable`** list. `--min-completeness <pct>` makes it a gate.

The decisive rule, **the one test**: *does the API accept this field as a
create/update input?* If yes it is a practitioner knob → `schema.attributes` as
`optional` (`+computed` only when the server defaults it to a non-pinnable value;
prefer `default: <literal>`). If it's pure server-owned output (timestamps,
`related`, `summary_fields`, `url`, `detail`, counters, `*_role`) → `ignore_server_fields`.
**FK/reference ids and behavior toggles (`enable_*`, `*_enabled`, the whole `ask_*` /
`*_on_launch` family) ARE settable** — modeling a handful while dumping dozens of
settable fields to hit 100% is **green-washing**.

**Make the gate mechanical, not judgement-based: feed a request schema.**
`settable_coverage` derived from the cassette alone is blind to inputs you never
modeled/sent (false `1.0`). Whenever the API serves a schema (OpenAPI, or a DRF
`OPTIONS` `actions.POST` envelope), pass it as `--metadata`/`--openapi` to **both**
`completeness` and `conform --emit-proof` — `ignored_settable` then names every
dumped input, and `emit-proof` *refuses* a green-washed contract
(`green-washing refusal: ignored N settable inputs …`).

Kind-specific: a read-only **DataSource/Ephemeral** has no settable inputs, so
routing the envelope to `ignore_server_fields` is legitimate — instead model the
practitioner-useful outputs as `computed`. An **action/ephemeral** is low-by-design
on completeness — judge by `action_returns_expected`, not a percentage, and don't
point `--min-completeness`/`--emit-proof` at it.

**The full classification rubric, the green-washing blind-spot, the field-suggestion
catalog, and the standard server-envelope starter set live in
`references/completeness-and-greenwashing.md` — read it when classifying fields or
completing a verbose resource.**

### 6. Emit proof only after targeted mutation evidence

After `conform` and `completeness` pass, run:

```bash
agentprovider conform contracts/widget.yaml .agentprovider/cassettes/widget.cassette.yaml --mutation-check --emit-proof
```

`--emit-proof` gates on **two** things: a passing `--mutation-check` *and* **100%
completeness** (every recorded field is either modeled or in `ignore_server_fields`)
— below that it refuses with `completeness N% is below proof threshold 100%` and
writes no sidecar. **If you also pass `--metadata`/`--openapi`** (recommended when
the API has a request schema), it adds a third gate: it refuses with a
`green-washing refusal: ignored N settable inputs …` and writes no sidecar when a
settable input is parked in `ignore_server_fields` — so a thin contract can't be
proven. With no request-schema flag this gate is skipped and emit-proof behaves
exactly as before (offline cassette-only proofs are unaffected). The sidecar, when written, is named `<type>.proven.json` — the
contract file's `.yaml` extension is **replaced**, not appended (a contract
`awx_org.yaml` yields `awx_org.proven.json`, not `awx_org.yaml.proven.json`). On a verbose API you reach 100% not by modeling every field but
by routing the **server-owned envelope** (relation links, summary blocks, URLs,
timestamps, computed status — anything the practitioner never sets or reads) into
`ignore_server_fields`. That is a non-request change, so it needs **no re-record** —
just re-run `completeness` then `--emit-proof`. **Reach the 100% by modeling the
settable inputs and ignoring only server-owned output — not by sweeping settable
knobs into `ignore_server_fields`** (that green-washes the gate; see the
completeness step).

Because of that 100% gate, **`--emit-proof` is a resource / data-source step.** An
**action-only or ephemeral** contract is low-by-design on completeness (it models
only a verb's inputs + a few outputs), can never reach the 100% threshold, and so
gets **no `.proven.json`** — that is expected, not a failure. Prove those kinds at
`conform` (with `--mutation-check` for targeted-mutation evidence); don't try to
inflate their completeness to force a sidecar.

`--mutation-check` mutates contract-relevant response evidence first: computed
outputs pinned in `conformance.example`, `conformance.expect` leaves, identity
response fields, `field:`-mapped schema attributes, and status-sensitive invariant
responses. Ignored metadata and fallback response scalars are diagnostic only; a
proof pass requires at least one targeted mutation to make `conform` fail. If the
CLI reports `MUTATION CHECK INCONCLUSIVE`, add a real asserted output or
`conformance.expect` matcher instead of weakening the invariant set. A failed
targeted mutation check refuses `--emit-proof` and removes any stale
`<contract>.proven.json`. New proof sidecars must carry
`mutation_status: "passed_targeted"`; legacy boolean-only `mutation_check: true`
sidecars are not enough for `--require-proven` and should be regenerated with
`conform --mutation-check --emit-proof`.

## Get these right up front

These gotchas burn the most conform loops — fix them at authoring time, not one
failed run at a time. Each is a one-liner here; **the worked detail, the *why*, and
the symptom→fix mapping are in `references/gotchas.md` (and `references/repair-hints.md`)
— read it before your first record on a new API.**

- **`http://`/private host** → set both `allow_insecure` and `allow_private_host` in
  `connection` (else the SSRF guard rejects it at record/plan).
- **`auth` nests under `connection`** (not a top-level key) — the #1 first-`validate`
  failure. Canonical block: `connection: { base_url, allow_insecure, allow_private_host, auth: {...} }`.
- **`connection.base_url` must resolve at RUNTIME** — `${env.VAR}`/provider config,
  **never an undefined `${var.*}`**. `conform` doesn't exercise `base_url`, so a bad
  one passes every invariant and fails only at `terraform apply` (`unsupported
  protocol scheme ""`). Keep it identical across every contract.
- **Paths interpolate `${...}`, never `{...}`**; **base_url is ORIGIN only** — the
  full `/api/v2/...` path lives in each op.
- **Every op declares `expect_status`** — even a 200 read (no default-accept).
- **`update.body` and `conformance.update_to` must list the SAME attribute keys**
  (both ways) — a mismatch makes the replayed body miss the cassette.
- **Re-record only when you change a replayed REQUEST** (example/update_to input, op
  body); an assertion-only edit (expect matcher, action output) needs no re-record.
- **Reserved meta-args (`count`, …) can't be attribute names** (remap with `field:`); **object/nested attributes need an explicit `required`/`optional`/`computed`** marker.
- **Pick attribute shape by what the server does on OMIT** (four-way rubric: rejects →
  `required`; null/absent → `optional`; stable scalar → `optional+default:<lit>`;
  non-pinnable → `optional+computed`). Don't reflexively mark everything `computed`.
- **Identity token used in URLs → `type: string`**; an integer FK id in a path stays
  `type: number`.
- **Action `type` + verb concatenate to `dynamic_<type>_<verb>`** — for action
  `awx_job_launch` use `type: awx_job` + verb `launch`, NOT `type: awx_job_launch`.
- **An action input must not map to the same API field as a computed output** — name
  by-id inputs `<resource>_id` (`template_id`), never `id`.
- **Action contracts need a real computed-output check** (`action_returns_expected`
  with a pinned output) — a config-only action proof is vacuous.

### Proving by contract kind

- **Resource** — declare the CRUD invariant set (`id_is_computed_and_nonempty`,
  `create_echoes_inputs`, `read_matches_create`, `update_then_read_reflects`,
  `second_apply_is_noop`, `delete_then_read_404`). **Plus the required coverage
  floor:** an id-keyed resource with `read`+`update` must *also* declare
  `import_reconstructs` and `id_stable_across_update` — `conform` fails closed
  until they're present, so add them from the start (don't wait for the first
  failure).
- **DataSource** — declare `read_returns_expected` (drives `read` directly, no
  faked create). Put the read inputs *and* at least one real expected **computed
  output** in `conformance.example`; it fails closed if no computed output is
  verified, so don't leave it null.
- **Ephemeral** — declare `ephemeral_open_renew_close` (requires both
  `lifecycle.renew` and `lifecycle.close`). Open inputs go in `conformance.example`;
  computed outputs must come from the open response. If a credential is redacted in
  the fixture, set the example to the redacted form so the replay matches.
- **Action** — declare `action_returns_expected` and pin **stable** computed
  outputs (`status`, `name`) in `conformance.example` for it; declare
  `state_matches_expect` and put **server-assigned id-shaped** computed outputs
  in `conformance.expect.<attr>: {not_null: true}` (assert presence without
  freezing the per-run value). `bootstrap --kind action` emits this split by
  default; pinning a server-assigned id (e.g. `*_id`) in `conformance.example`
  is the failure mode `record` now warns about — it passes the frozen cassette
  but fails the next re-record. A config-only action proof with neither a
  stable pin nor a `not_null` expect is vacuous and should fail closed.
  An **action-only** contract is a `kind: Resource` with `actions` and **no
  `create` lifecycle**: the engine registers it as a Terraform Action
  (`dynamic_<type>_<verb>`), not a managed resource, so it is exempt from the
  CRUD coverage floor. Omit `body` on an action that POSTs nothing. See
  `references/contract-format.md` (actions) for the full worked contract and
  `references/terraform-usage.md` for the HCL.

## Two outcomes you must distinguish

`conform` failing is not always the same problem. Read the failure before
"fixing":

- **Contract invalid / cannot express the capability.** The contract won't load
  (a validation error), or the API genuinely needs something the contract format
  does not yet have. Do **not** paper over this by deleting the invariant or
  weakening the contract until a check passes — that green-washes an unproven
  contract (e.g. a contract with no auth that passes a weak read invariant has not
  actually authenticated). If the format can't express it, say so and stop; that
  is a real engine gap worth reporting, not an authoring failure.
- **Valid but invariant failed.** The contract loads and the failure is a fixable
  mismatch (wrong status, missing remap, perpetual diff). Apply the repair hint
  and re-run. This is the normal loop.

## Consuming the proven contract in Terraform

After `conform` and `completeness` both pass or are explicitly adjudicated, use
the contract in real Terraform to validate end-to-end with a live `apply`. The mapping is
mechanical and fully covered here and in `references/terraform-usage.md`:

- A contract `type: project` (with `create`) → resource `dynamic_project`; a
  `DataSource` → `data "dynamic_<type>"`; an `Ephemeral` → `ephemeral "dynamic_<type>"`.
- An **action-only** contract → a Terraform Action `dynamic_<type>_<verb>`, invoked
  from a sibling resource's `lifecycle { action_trigger { events = [after_create]
  actions = [action.<name>.<label>] } }`. Attach the trigger to a resource *other
  than* the action's target to avoid a `resource → action → resource` cycle.
- Wire foreign keys through computed ids (`project = dynamic_team.main.id`)
  so Terraform builds the dependency graph; keep credentials in `${env.*}`/`${var.*}`.

`references/terraform-usage.md` has the full HCL surface — provider block,
`dev_overrides`, the resource/action/data-source/ephemeral forms, the
`action_trigger` pattern and cycle gotcha, and a complete worked graph.

## Security guidance the engine can't enforce for you

- Prefer `auth.type: header` / `basic` / `oauth2` over `query`. Query auth puts
  the secret in the URL, which is logged server-side beyond the redactor's reach —
  emit `auth.type: query` only when the API mandates it.
- Mark every credential-bearing attribute `sensitive: true`. The transport
  redactor scrubs headers/bodies/URLs but **cannot reach Terraform attribute
  values** — a credential surfaced as a non-sensitive attribute leaks to state.
  (Load-time validation rejects credential-named attributes that aren't sensitive,
  but don't rely on it — name and mark deliberately.)
- Source credentials from `${env.VAR}` / `auth.env` / provider config, never a
  literal secret committed in the YAML.

## Reference files

Read these as needed — don't load them all up front:

- `references/contract-format.md` — every contract block and field, with the
  newer capabilities (query/basic/oauth2 auth, async redirect/expiry,
  carry_on_read, normalize, pagination metadata + start-index).
- `references/cli-loop.md` — exact `bootstrap` / `introspect` / `record` /
  `conform` / `completeness` flags and the stable JSON shapes (including
  `introspect`'s text default and JSON mode for agents).
- `references/repair-hints.md` — the standard invariant set, what each invariant
  actually compares, and the repair-hint catalog (symptom → fix → why).
- `references/gotchas.md` — the full "get these right up front" catalog (the
  one-liners above, with worked detail and the four-way attribute-shape rubric).
- `references/completeness-and-greenwashing.md` — the field-classification rubric,
  the green-washing blind-spot and `--metadata` gate, and the server-envelope set.
- `references/terraform-usage.md` — the HCL consumption surface: resource / data
  source / ephemeral / action naming, the `action_trigger` pattern and cycle
  gotcha, FK wiring, and a complete worked graph for the live `apply` proof.

## Done means

Done means, in this exact order:

1. Fresh or changed contracts with a live schema-bearing endpoint used `agentprovider introspect` for read-only field discovery before bootstrapping/authoring, or the summary states why no live discovery path existed.
2. Every fresh or changed contract was seeded with `agentprovider bootstrap` (or, if deliberately hand-authored, that exception is stated in the summary and the draft was confirmed to load under strict decoding).
3. Fresh or changed contracts are recorded with `agentprovider record` against the intended target.
4. `agentprovider conform <contract> <cassette>` returns `overall_passed: true` (JSON by default) with a non-empty `conformance.invariants` set for every contract.
5. `agentprovider completeness <contract> <cassette>` is run for every contract, and any important `missing` fields are modeled or explicitly judged out of scope — with settable inputs modeled as `optional`(`+computed`) attributes, not swept into `ignore_server_fields` to inflate the number (green-washing). A resource/data source should expose the practitioner-relevant settable inputs the API accepts, not a thin handful.
6. For provider-authoring tasks, the Terraform example that consumes the contracts applies successfully against the intended runtime.
7. The cassette is redacted and reviewed, and credentials are sourced from env/provider config, not committed.

Only report `PROVEN` after all applicable steps above are complete.
