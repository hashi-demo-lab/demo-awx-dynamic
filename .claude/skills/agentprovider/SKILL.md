---
name: agentprovider
description: >-
  Author and prove an agentprovider YAML contract that turns an HTTP/REST API into
  a Terraform provider, data source, ephemeral resource, or custom action —
  config-driven, no hand-written Go. Use when someone wants Terraform to drive an
  HTTP API: an OpenAPI spec or REST endpoints made into a provider/resource/data
  source, a short-lived token that never hits state, a counter's up/down verbs, or
  an async 202-poll create. Also triggers on agentprovider,
  terraform-provider-dynamic, or `agentprovider bootstrap/record/conform`
  (including repair-hint questions). Drives the bootstrap → record → conform →
  self-correct loop until the contract is proven against recorded responses. NOT
  for running an already-authored provider (docs/RUNNING.md), hand-writing a
  provider with terraform-plugin-framework, editing the engine internals, or
  debugging an existing third-party Terraform provider.
---

# Authoring an agentprovider contract

agentprovider builds a Terraform provider by **interpreting a declarative YAML
contract at runtime** — there is no per-API Go to write. Author one contract for
a target API and **prove it correct** against recorded responses, using the
`agentprovider` CLI's three seams. The contract is the unit of work; the
conformance verdict is the definition of done.

The mandatory loop, in order:

```
bootstrap (seed)  →  record (capture a cassette)  →  conform (machine verdict)  →  apply repair_hints  →  re-run until overall_passed  →  completeness (coverage gate)  →  Terraform apply (runtime proof)
```

**`bootstrap` is step 1 and is mandatory — do not skip it.** Every new or changed
contract MUST be seeded with `agentprovider bootstrap` (from an OpenAPI spec or a
sample JSON response) before you record. `record` *replays an existing contract*,
so a contract has to exist first — there is no "record first" mode, and
hand-writing the YAML from scratch to bypass `bootstrap` is **not** the default
path. _Narrow exception:_ if you deliberately hand-author instead of
bootstrapping, you MUST (a) state that and why in your summary, and (b) confirm the
draft loads under strict decoding before recording — bootstrap output is valid by
construction, whereas hand-written YAML is exactly where load errors creep in
(e.g. an unquoted `${id}` inside a flow-mapping `path:` breaks YAML; quote such
paths).

`conform` returning `overall_passed` is the correctness loop; `completeness` is a
mandatory follow-on gate (step 4) that checks the contract models enough of the
API surface. Do not skip completeness when claiming a contract is done or proven.
For Terraform-provider authoring tasks, do not print or report `PROVEN` until all
contracts conform, completeness has been checked for every contract, and the
Terraform example has applied successfully.

All commands below use the `agentprovider` CLI; make sure it's available on your
PATH before you start. The input can be an **OpenAPI spec**, a **sample JSON
response**, or just a base URL plus your knowledge of the API's shape. If the user
only wants to *run* an existing provider, that's `docs/RUNNING.md`, not this skill.

## The loop in detail

### 1. Seed a draft with `agentprovider bootstrap` — REQUIRED FIRST STEP

**Always start here for a new or changed contract. Do not hand-author from scratch
to skip `bootstrap`** (see the narrow exception in the loop note above).

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
practitioner fields**, not lightly tweak: keep the handful you actually set or
read, and route server-owned churn to `ignore_server_fields`.
The two new kinds emit valid but **not-yet-conforming** drafts: an ephemeral draft
carries placeholder `renew`/`close` paths, and an action draft carries placeholder
`conformance.example` output values — both must be repaired before `conform` passes
(see `references/repair-hints.md`).

Then read the draft and fill the gaps by hand against the contract format — see
`references/contract-format.md` for every block and field. Common things
bootstrap can't infer: `identity.response_field` for a genuinely non-conventional
id (the common single-path-param by-id case is auto-detected; see above),
`refresh_after` (empty write responses), `ignore_server_fields` (server
timestamps), `auth`, `async`, `pagination`, `carry_on_read`/`normalize`,
ephemeral `renew`/`close` paths, and an action's real expected output value.

### 2. Record a cassette with `agentprovider record`

One live pass captures byte-accurate responses into a replayable cassette and
(with `--suggest`) proposes refinements such as `ignore_server_fields` candidates.

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
- **`--suggest` is resource-tuned.** On an action-only contract it may propose an
  `identity.response_field` (an action has no identity) — ignore that one;
  `unmodeled_fields`/`ignore_server_fields` suggestions still apply.
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

### 3. Get a machine verdict with `agentprovider conform`

```bash
agentprovider conform contracts/widget.yaml .agentprovider/cassettes/widget.cassette.yaml --json
```

The JSON is stable: `{contract, overall_passed, results[], repair_hints[],
summary}`. Each failing result carries `expected`, `actual`, `contract_path`, and
`suggested_fix`; `repair_hints` ranks unique fixes in failure order. Loop:

1. If `overall_passed` is true — done.
2. Otherwise apply the top `repair_hint` (see `references/repair-hints.md` for what
   each one means and *why*), re-run `conform`, repeat.

A contract must **declare the invariants it wants** under `conformance.invariants`
— the harness fails closed on a contract with zero checks (a green run with no
invariants is not a pass). Start from the standard set in
`references/repair-hints.md`.

### 4. Check completeness with `agentprovider completeness`

This step is mandatory after `conform` passes and before any final Terraform
runtime proof. Run it for every freshly authored or changed contract. If
completeness reports important missing fields, model them or deliberately explain
why they are out of scope before proceeding. Do not treat a green `conform` result
alone as sufficient proof.

`conform` proves the contract is *correct*; it does not prove it is *complete*. A
contract can pass every invariant while modeling only a handful of an endpoint's
fields. After it conforms, measure how much of the API surface you actually model:

```bash
# offline: diff against the fields recorded in the cassette
agentprovider completeness contracts/widget.yaml .agentprovider/cassettes/widget.cassette.yaml --json
# dynamic: diff against what the live API returns right now
agentprovider completeness contracts/widget.yaml --base-url https://api.example.com --min-completeness 90
```

It reports `completeness_percent`, the `missing` fields (the API returns them but
no attribute models them), and `extra` (modeled but not seen — usually fine). The
reference field set is generic and dynamic: the fields the API *actually returns*,
from the cassette (offline) or a live read (`--base-url`). `--min-completeness`
makes it a gate (non-zero exit below the threshold). Model the missing fields you
care about (as `computed` for server-owned values, `optional` for settable ones),
or add genuinely irrelevant ones to `ignore_server_fields`; then re-record and
re-check. Weigh `missing` by **practitioner relevance, not count** — some entries
are artifacts of a response shape you don't model (an error/`detail` envelope, a
delete body) and aren't worth modeling. Note: response-union can't see *write-only*
inputs the server never echoes — model those from the API's docs.

Completeness is a **resource / data-source** gate. An **action-only or ephemeral**
contract models only the verb's inputs plus a few computed outputs, so its
completeness against a full read payload is **low by design — not a defect**. Judge
an action by `action_returns_expected` (does it project the outputs you claimed?),
not by a percentage, and don't point `--min-completeness` at one.

`record --suggest` also flags `unmodeled_fields` (recorded response fields with no
matching attribute) so you catch gaps at record time.

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
- **`update_to` and `update.body` list *every* request-body attribute, not just
  the changed one** — include unchanged required fields in `conformance.update_to`.
  The update body is built only from keys present, so a partial `update_to`
  changes the replayed request body and won't match the recorded update.
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
- **Action** — declare `action_returns_expected` and include action inputs plus at
  least one expected computed output in `conformance.example`, so replay proves
  the action projection rather than only proving the HTTP call did not error. An
  **action-only** contract is a `kind: Resource` with `actions` and **no `create`
  lifecycle**: the engine registers it as a Terraform Action (`dynamic_<type>_<verb>`),
  not a managed resource, so it is exempt from the CRUD coverage floor. Omit `body`
  on an action that POSTs nothing. See `references/contract-format.md` (actions) for
  the contract and `references/terraform-usage.md` for the HCL.

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
- `references/cli-loop.md` — exact `bootstrap` / `record` / `conform` /
  `completeness` flags and the stable `--json` shapes.
- `references/repair-hints.md` — the standard invariant set, what each invariant
  actually compares, and the repair-hint catalog (symptom → fix → why).
- `references/terraform-usage.md` — the HCL consumption surface: resource / data
  source / ephemeral / action naming, the `action_trigger` pattern and cycle
  gotcha, FK wiring, and a complete worked graph for the live `apply` proof.

## Done means

Done means, in this exact order:

1. Every fresh or changed contract was seeded with `agentprovider bootstrap` (or, if deliberately hand-authored, that exception is stated in the summary and the draft was confirmed to load under strict decoding).
2. Fresh or changed contracts are recorded with `agentprovider record` against the intended target.
3. `agentprovider conform <contract> <cassette> --json` returns `overall_passed: true` with a non-empty `conformance.invariants` set for every contract.
4. `agentprovider completeness <contract> <cassette> --json` is run for every contract, and any important `missing` fields are modeled or explicitly judged out of scope.
5. For provider-authoring tasks, the Terraform example that consumes the contracts applies successfully against the intended runtime.
6. The cassette is redacted and reviewed, and credentials are sourced from env/provider config, not committed.

Only report `PROVEN` after all applicable steps above are complete.
