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

**`bootstrap` is the mandatory draft-creation step — do not skip it.** Every new
or changed contract MUST be seeded with `agentprovider bootstrap` (from an OpenAPI
spec or a sample JSON response) before you record. `record` *replays an existing
contract*, so a contract has to exist first — there is no "record first" mode, and
hand-writing the YAML from scratch to bypass `bootstrap` is **not** the default
path. Run `introspect` first when the live API can describe its settable surface;
then use those findings to guide the bootstrap inputs and first repair pass.
_Narrow exception:_ if you deliberately hand-author instead of
bootstrapping, you MUST (a) state that and why in your summary, and (b) confirm the
draft loads under strict decoding before recording — bootstrap output is valid by
construction, whereas hand-written YAML is exactly where load errors creep in
(e.g. an unquoted `${id}` inside a flow-mapping `path:` breaks YAML; quote such
paths).

`conform` returning `overall_passed` is the correctness loop; `completeness` is a
mandatory follow-on gate that checks the contract models enough of the
API surface and classifies missing fields for repair. Do not skip completeness
when claiming a contract is done or proven.
For Terraform-provider authoring tasks, do not print or report `PROVEN` until all
contracts conform, completeness has been checked for every contract, and the
Terraform example has applied successfully.

All commands below use the `agentprovider` CLI; make sure it's available on your
PATH before you start. The input can be an **OpenAPI spec**, a **sample JSON
response**, or just a base URL plus your knowledge of the API's shape. If the user
only wants to *run* an existing provider, that's `docs/RUNNING.md`, not this skill.

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

For a reviewed local/dev target on a private host, add `--allow-private-host`.
For credentialed `http://`, add `--allow-insecure` only after confirming the
target is safe to receive bearer credentials over plaintext.

`--auth-env` takes an environment variable **name**, not a token value. The
command tries `OPTIONS` first and reuses the same DRF metadata parser as
completeness; when `OPTIONS` is unavailable it falls back to one `GET` sample with
`confidence: reduced`. Default output is human-readable text; use `--format json`
or `--json` when another agent/tool will consume the result.

Treat high-confidence `OPTIONS` rows as authoring candidates (`required`,
`optional+default`, `optional+computed`, or `computed`). Treat sample-derived
rows, nested paths, and malformed descriptor metadata as review-only signals: they
intentionally do not include a copyable `attribute` snippet until you confirm
requiredness, settable status, type, and object/list shape.

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

From an OpenAPI spec the importer now also: marks `format: password` and
credential-named fields `sensitive: true` (recursively, including list/map
element objects); carries a `default` for non-sensitive string/bool attributes
(other-typed or sensitive defaults are dropped with a one-line stderr notice, so
a secret is never written into the contract); and, for a by-id read with a single
path parameter, auto-detects the identity attribute and rewrites the read path
token to it (so `/pets/{petId}` → `${id}`). Use `--alias <param>=<attribute>` to
force that link when names don't line up, and `--ignore <name>` (repeatable,
dot-path like `category.id`) to drop pagination/noise fields from the schema and
request bodies.

`--alias` and `--ignore` shape the **OpenAPI** importer only — a `--response` seed
has no such pruning, and it mirrors the *whole* example faithfully. For a verbose
API that example is mostly server-owned noise (`related`, `summary_fields`,
timestamps), so a `--response` draft is something you **rewrite down to the
practitioner fields**, not lightly tweak: model the fields a practitioner sets or
reads (settable inputs as `optional`/`optional+computed`, server values as
`computed`), and route only server-*owned* churn to `ignore_server_fields`. Don't
collapse settable inputs into `ignore_server_fields` — see the completeness step on
green-washing.
The two new kinds emit valid but **not-yet-conforming** drafts: an ephemeral draft
carries placeholder `renew`/`close` paths, and an action draft carries placeholder
`conformance.example` output values — both must be repaired before `conform` passes
(see `references/repair-hints.md`).

Then read the draft and fill the gaps. Ask the CLI for authoritative rules before
reading Go source or mirrored prose:

```bash
agentprovider schema --format json
agentprovider invariants contracts/widget.yaml
agentprovider describe 'schema.attributes.<name>.type'
agentprovider describe conformance.invariants
agentprovider validate contracts/widget.yaml
```

`agentprovider schema` emits the JSON Schema for the **whole contract file
format**. Use it for editor autocomplete, agent-side structural checks, or
validating bootstrap output before semantic checks. `--format yaml` emits the
same schema as YAML. Do not confuse the contract format schema with the
contract's own `schema.attributes` block: `schema.attributes` defines
Terraform-facing attributes; the contract format schema validates the YAML
document shape. Use `agentprovider describe <field-path>` for authoring help on
individual fields. Semantic checks such as pagination consistency, credential
sensitivity, and conformance coverage still come from `agentprovider validate` /
`conform`.

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

It reports `completeness_percent`, the `missing` fields (the API returns them but
no attribute models them), and `extra` (modeled but not seen — usually fine). It
also emits `fields[]` classifications and `suggestions[]` review artifacts. Use
those before source-diving or making name-based schema edits:

- `optional` / `optional_computed_defaulted` with high confidence can become a
  schema attribute suggestion. A field **already modeled** `optional` (not
  `computed`) that the cassette shows the server defaults is surfaced as a
  `promote_to_optional_computed` correction. When the recorded omit-create
  response is a **stable scalar literal**, the suggestion now carries
  `optional: true` + `default: <literal>` (text: *"set default:&lt;v&gt; on &lt;path&gt;
  to keep it plan-known and preserve drift detection"*) — the CLI pins the literal
  from that create-filtered value. When the default isn't a pinnable scalar
  (object/list, canonicalized, variable), it falls back to a `promote_schema_attribute`
  carrying `optional: true, computed: true`. Apply whichever it emits, or the
  `optional_default_consistency` conform gate fails closed. Prefer `default:` over
  `computed:` whenever a literal is offered — see the four-way rubric under "Get
  these right up front".
- `volatile` / `ignore_server_field` candidates usually belong in
  `ignore_server_fields`.
- `needs_probe` means the current evidence is not enough to promote the field.
  Add `--probe-field <path> --allow-probes` for read-only evidence, and add
  `--allow-mutations` only when you explicitly accept create/delete probe risk.
- `--emit-judge-input`, `--judge-input`, and `--judge-command` are advisory only;
  model output must never determine proof readiness.

The reference field set is generic and dynamic: recorded request/response bodies,
cassette responses, OpenAPI request/response schemas, optional metadata/docs
evidence, or a live read (`--base-url`). `--min-completeness` makes it a gate
(non-zero exit below the threshold). Model the missing fields you care about, or
add genuinely irrelevant ones to `ignore_server_fields`; then re-record as
needed, re-run `conform`, and re-check completeness. Weigh `missing` by
**practitioner relevance, not count** — some entries are artifacts of a response
shape you don't model (an error/`detail` envelope, a delete body) and aren't
worth modeling. Note: response-union can't see *write-only* inputs the server
never echoes — model those from the API's docs/specs.

**`ignore_server_fields` is for server-*owned* output only — not a dumping ground
to hit a completeness number.** Before you ignore a field, ask the one question
that decides its class: **does the API accept this field as a create/update
input?** (Check the request schema — OpenAPI request body, an `OPTIONS`/`POST`
field listing, or the create-body the API documents.) If yes, it is a
**practitioner knob** and belongs in `schema.attributes` as `optional: true`, *not*
in `ignore_server_fields`. When the server *supplies a value you didn't send*, the
field is server-defaulted and must absorb that value — but **prefer
`optional + default: <literal>` over `optional + computed`** whenever the omit-default
is a **stable scalar** (a string/number/bool literal, including `""`, `0`, `false`,
`"run"`): a static default keeps the unset value plan-known **and** preserves drift
detection, where `computed` is drift-blind on the unset field. Reserve
`optional + computed` for defaults that can't be pinned to a literal — a
canonicalized form of your input, or an object/list/variable default. Do **not**
mark a field computed merely because the server echoes it back: an optional input
the server leaves **null/absent** when omitted should stay `optional`-only (plain).
Reserve `ignore_server_fields` for fields the practitioner
can never set — timestamps, `related`/`_links`, `summary_fields`, computed status,
counters, error envelopes (`detail`). **A foreign-key / reference id is a settable
input, not server-owned** — `*_credential`, `execution_environment`,
`default_environment`, `*_environment`, a parent/`organization`/`project` id, and
similar reference fields are accepted on create/update (the API lists them in its
request schema / `OPTIONS` POST), so they belong in `schema.attributes` as
`optional` FKs, not swept into `ignore_server_fields` as "server-owned." The tell
is that the field *names a related object*: if the practitioner could point it at a
different object, it is a knob, not envelope. **Behavior toggles are settable knobs
too** — boolean/enum flags such as `enable_*`, `allow_*`, `*_enabled`, and the whole
`ask_*` / `*_on_launch` family that a verbose API accepts in its create/update body
configure how the resource behaves; a verbose object can carry a dozen-plus of them,
and they are the single biggest green-washing trap (easy to wave off as "launch-time
behavior" and dump). If the request schema accepts the flag, model it `optional`
(`+computed` when the server defaults it) — do not park it in `ignore_server_fields`.
The completeness gate may not catch any of this on an API that exposes no request
schema (response-union evidence can't tell a settable input from a server-supplied
one), so it is on you to classify by the one test — **"does the create/update body
accept this field?"** — not by where the value happens to come from or whether it
"feels" like core config. Ignoring a *settable* field only to clear the
gate is **green-washing**: completeness reads 100% but you have shipped a resource
that can't configure most of the API (a verbose object can have dozens of real
optional inputs — limits, tags, timeouts, feature toggles — and burying them turns
a rich resource into a near-empty one). Reach 100% the right way: model the
settable fields a practitioner would reasonably set as `optional`(`+computed`), and
ignore only the genuinely server-owned remainder. A quick self-check on any
contract: count the `optional`/`optional+computed` attributes against the API's
settable-input list — if you're modeling a handful while ignoring dozens of
settable fields, you green-washed, not completed.

**Let the tool measure green-washing, not just your judgement.** `completeness`
reports a **`settable_coverage`** ratio and an **`ignored_settable`** list on every
run — it derives "settable" from the **recorded create/update request bodies in the
cassette**, so you get the signal for free with no extra flag. Read it on every
resource: a `settable_coverage` below `1` (or a non-empty `ignored_settable`) means
you parked a field you are *actually sending* into `ignore_server_fields` — model it
`optional` instead.

But understand the **blind spot**: cassette-derived settable only sees fields the
contract *already sends*. An input the API accepts that you never modeled and never
sent leaves **no request-body evidence**, so it is invisible — `settable_coverage`
reads a false `1.0` even when you've dumped a dozen real knobs. That false-green is
exactly the green-washing failure mode, and it is sample-dependent on a verbose
object (the same prose guidance has produced both 0 and 22 dumped toggles on
different runs). **The fix that makes quality reproducible is to feed a request
schema**, which lists *every* accepted input the cassette can't see:

```bash
# OpenAPI: you already have the spec
agentprovider completeness contracts/widget.yaml <cassette> --openapi spec.yaml --operation createWidget
# DRF / Django-REST API (no OpenAPI): use introspect for discovery before
# authoring. If a reusable proof gate needs --metadata, save the reviewed full
# OPTIONS envelope (or wrap a reviewed POST map as {"actions":{"POST":...}}).
agentprovider introspect /api/v2/widgets/ --base-url "$BASE_URL" --auth-env AWX_TOKEN --format json
agentprovider completeness contracts/widget.yaml <cassette> --metadata widget.options.json --min-settable-coverage 90
```

With a schema fed, `ignored_settable` now names every accepted input you dumped (not
just the ones you happen to send), `--min-settable-coverage <pct>` makes a thin
contract exit non-zero, and — crucially — **`conform --mutation-check --emit-proof`
takes the same `--metadata`/`--openapi` and _refuses to write the proof_** with
`green-washing refusal: ignored N settable inputs …`. So **whenever the API serves a
schema (OpenAPI, or a DRF `OPTIONS` envelope containing `actions.POST` metadata), pass it to both
`completeness` and `emit-proof`** — a green-washed contract then *cannot* be proven,
turning the prose guard above into a mechanical gate. (Credential and read-only
fields are excluded automatically, so a sensitive or server-assigned field in
`ignore_server_fields` never trips it.) Only when the API exposes **no** schema at
all do you fall back to the cassette-only signal plus the one-test judgement above.

This guard is about **settable inputs**, which only exist on a contract with a
create/update body (resources). A **read-only DataSource or Ephemeral has no
settable inputs** — every field is a computed output — so routing the
non-projected server envelope into `ignore_server_fields` to reach completeness is
*legitimate*, not green-washing (nothing a practitioner could set is being hidden).
For those kinds the quality bar is the inverse: **model the practitioner-useful
outputs as `computed`** (don't leave the data source projecting three fields), then
ignore the remaining pure envelope. Don't react to the green-washing rule by
refusing `ignore_server_fields` and leaving a read-only contract stuck at low
completeness — that fails the gate without improving quality.

Completeness is a **resource / data-source** gate. An **action-only or ephemeral**
contract models only the verb's inputs plus a few computed outputs, so its
completeness against a full read payload is **low by design — not a defect**. Judge
an action by `action_returns_expected` (does it project the outputs you claimed?),
not by a percentage, and don't point `--min-completeness` at one. That same
low-by-design completeness is why `--emit-proof` (which requires 100%) does not
apply to action/ephemeral kinds — prove them at `conform`, not with a sidecar (step 5).

`record --suggest` also flags `unmodeled_fields` and field-level suggestions so
you catch gaps at record time. It still does not edit the contract for you.

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

These gotchas burn the most conform loops. Fix them at authoring time rather than
discovering them one failed run at a time; `references/repair-hints.md` carries
the *why* and the symptom→fix mapping for each.

- **A plaintext-`http://` or private/loopback target needs both `allow_insecure`
  and `allow_private_host` in `connection`** — set them up front for a local/dev or
  internal API (e.g. `http://localhost:...`, a `10.`/`192.168.` host). Otherwise the
  engine's transport/SSRF guard rejects the host and you only discover it at
  `record`/`plan` time. The skill's other examples assume a public HTTPS API, where
  neither is needed.
- **Paths interpolate `${...}`, never `{...}`** — `path: /widgets/${id}`, async
  `status_path: /jobs/${job_id}`. A bare `{id}` is a literal and won't match the
  recording.
- **Every operation declares its happy-path `expect_status`** — the engine has no
  default-accept, so even a 200 read needs `expect_status: [200]`. A missing read
  status is the most common "first conform fails"; the auto-hint may misattribute
  it to `create.body`, so when you see `expected status in [], got 200`, add the
  status to the op named in the failing result.
- **`update_to` and `update.body` must list the *same* request-body attributes —
  the symmetry runs both ways.** Include unchanged required fields in
  `conformance.update_to` (the body is built only from keys present, so a partial
  `update_to` won't match the recorded update). The inverse bites just as hard and
  is easier to miss: **any attribute you put in `update.body` must also appear in
  `update_to` with a value** — `record` sends that attribute on the live PATCH/PUT
  (a modeled optional is sent even as `null`), but `conform` rebuilds the request
  from `update_to`'s keys, so an attribute in `update.body` that `update_to` omits
  makes the replayed body *shorter* than the recorded one → a byte-replay miss (`no
  recorded interaction for PATCH …`). If a field is never actually changed by the
  update, drop it from `update.body` rather than carrying it as a null; if it is
  changed, give it a value in `update_to`. Keep the two key sets identical.
- **The example must match the request the recorder will replay — and re-record
  after you change it.** Two recurring traps: (1) an `optional: true, computed: true`
  field the server defaults (e.g. `max_hosts`) is still sent in the body, so it must
  appear in `conformance.example`/`update_to` with the server's value or the replay
  misses the cassette; (2) a value the server canonicalizes (trims a trailing
  newline, lowercases) must be written in its server-returned form. Re-record only
  when you change what gets **replayed as a request** — an `example`/`update_to`
  input that lands in a body or path, or an op's `body`: then **re-run `record`** so
  the cassette's requests match (conform replays byte-for-byte, so a stale cassette
  fails). Editing a value that is purely an **assertion target** — an action's
  expected computed *output*, a `conformance.expect` matcher — changes no request, so
  it needs **no** re-record; just re-run `conform`. (Knowing the difference saves
  needless live calls, especially for actions that launch real work.)
- **Reserved Terraform meta-args (`count`, …) can't be attribute names** — expose
  the API field under another name with `field:` (attribute `value`, `field: count`).
- **Object/nested attributes need an explicit `required`/`optional`/`computed`
  marker** — including the fields *inside* an object.
- **Pick the attribute shape by what the server does when the field is OMITTED**
  (the four-way rubric). Reflexively marking every optional `computed` is a quality
  regression — a `computed` attribute reports no drift when it's unset, so you lose
  change detection on genuine inputs. Decide instead:
  - **Server rejects omission** → `required`.
  - **Server returns null/absent** (genuinely unset) → `optional` (plain). Drift-detecting.
    Use this *only* when you've confirmed the server returns null/absent on omit.
  - **Server returns a stable scalar literal** (string/number/bool — including `""`,
    `0`, `false`, `"run"`) → **`optional: true, default: <literal>`** (no `computed:`
    key). **Preferred:** plan-known **and** drift-detecting. The CLI auto-suggests
    this for *meaningful* scalars (`"run"`, `1`, `3`); for `0`/`false`/`""` it stays
    silent (its `IsMeaningfulDefaultValue` heuristic skips them), so **you** declare
    the `default:` from the API's docs/observed behavior.
  - **Server returns a non-pinnable default** (object/list/map, a canonicalized form
    of your input, an env-dependent/variable value) → `optional: true, computed: true`.
    Apply-safe but drift-blind on the unset field — the accepted cost when no stable
    literal exists.
  - **Pure server-owned output** (never settable) → `computed` only.
  - Note: a server that echoes **any** value on omit (even `0`/`false`/`""`) is
    server-defaulting — never leave it plain `optional` (that re-introduces "Provider
    produced inconsistent result after apply"); it needs `default:` or `computed`.
  - **YAML shape ≠ generated schema.** A declared `default:` forces the *generated*
    framework attribute to optional+computed+default (the framework requires it), so
    keep `computed:` **absent** in the contract YAML — `optional_default_consistency`
    checks exactly the `optional`-not-`computed` attributes, and the drift-detection
    win comes from the default being a plan-known literal, not from the missing key.
  See `references/contract-format.md` (`default:`) for the worked example.
- **An action's input attribute must not map to the same API field as a computed
  output** — a by-id action that interpolates `${id}` into its path is the classic
  trap: if a computed output already maps `field: id` (the id the action returns),
  naming the path input `id` too makes *two* attributes claim API field `id`, and
  the contract fails to load (`attributes "a" and "b" both map to API field
  "id"`). It surfaces only at `record`/replay, so it costs a re-record. Name by-id
  inputs distinctly — `<resource>_id` (`template_id`, `pipeline_id`) — which is the
  real reason the worked example's input is `pipeline_id`, never `id`.
- **Custom-action invariants are name-keyed** — `action_increment_changes_count` /
  `action_decrement_changes_count` drive actions named exactly `increment` /
  `decrement`; match the names.
- **Choose an action's `type` so that `<type>_<verb>` equals the Terraform action
  id you want** — the action surfaces as `dynamic_<type>_<verb>`, built by
  concatenation. If you want the action `awx_job_launch`, set `type: awx_job` with
  verb `launch` (→ `dynamic_awx_job_launch`); do **not** set `type: awx_job_launch`,
  which yields `dynamic_awx_job_launch_launch` and a plan-time "no action schema for
  …" error after you've already recorded. The verb lives in the action, not the
  type — split the desired name at the trailing verb and put the stem in `type`.
  `validate` and `preflight` now emit a non-fatal advisory when `type` ends in a
  declared verb (naming the doubled id and the split fix), so you catch this before
  recording — but the contract still loads, so heed the advisory rather than relying
  on it to block.
- **Action contracts need a real computed output check** — for action-only
  contracts, declare `action_returns_expected` and put at least one computed
  response field in `conformance.example` (for example `run_id`). A config-only
  action proof with no computed output expectation is vacuous and should fail
  closed.
- **An identity used verbatim in URLs should be `type: string`** unless the id is a
  canonical integer. Terraform stores numbers as floats, so a non-canonical token
  (`007`, `1e6`, `1.0`) is canonicalized and the rebuilt URL won't match. `conform`
  enforces this and emits a "declare type: string" hint, so you catch it up front.
  Rule of thumb: the resource's own **identity token → `type: string`**; an integer
  **foreign-key id used in a path** (`project_id`, `inventory`) stays `type: number`
  — a canonical integer renders cleanly into `${...}`, no float artifact.

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
