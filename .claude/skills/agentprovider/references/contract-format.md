# agentprovider contract format

This file is narrative context for repairing a bootstrapped draft. The
authoritative, machine-readable contract schema and validation rules come from
the CLI:

```bash
agentprovider schema --format json
agentprovider invariants contracts/widget.yaml
agentprovider describe 'schema.attributes.<name>.type'
agentprovider describe conformance.invariants
agentprovider validate contracts/widget.yaml
```

For editor integration or agent-side structural validation, write the contract
schema to a file:

```bash
agentprovider schema --format json > agentprovider-contract.schema.json
agentprovider schema --format yaml
```

`agentprovider schema` emits a JSON Schema document for the whole YAML contract
file. It validates structure, not every semantic rule: cross-field rules still
come from `agentprovider validate`, behavioral proof still comes from `conform`,
field-level format help comes from `agentprovider describe <field-path>`, and
evidence-backed missing-field repair guidance comes from
`agentprovider completeness` classifications and suggestions.

Use this reference to understand the shape and examples, not as licence to skip
`bootstrap`, which is a mandatory first step — see SKILL.md. Strict decoding is
on: an **unknown key fails the load**, so a typo'd field is caught immediately
rather than silently ignored.

## Top level

```yaml
apiVersion: agentprovider/v1     # format version identifier (literal; unchanged by the tool rebrand)
kind: Resource            # Resource | DataSource | Ephemeral  (default Resource)
type: widget              # unique provider-local type name → dynamic_widget
connection: { ... }
schema: { attributes: { ... } }
identity: { ... }         # resources only
lifecycle: { ... }
actions: { ... }          # custom non-CRUD verbs (map name → operation)
ignore_server_fields: [createdAt, updatedAt]
conformance: { ... }
```

## connection

```yaml
connection:
  base_url: "${var.base_url}"      # or a literal https URL; ${env.VAR} allowed
  headers: { Accept: application/json }
  allow_insecure: false            # required to use a plaintext http:// base_url
  allow_private_host: false        # required for private/loopback/metadata hosts (tests/private APIs only)
  request_content_type: application/json   # or application/x-www-form-urlencoded (aliases: form, form-encoded) / text/plain
  timeout_seconds: 30              # 0 = transport default
  max_retries: 3                   # 0 = default; negative disables retry
  retry_base_backoff_ms: 200
  retry_nonidempotent_on_throttle: false   # opt POST/PATCH into 429/503 retry (only if idempotent-safe)
  auth: { ... }
```

### auth

`auth.type` is one of `header`, `query`, `basic`, `oauth2`. A credential slot is
satisfiable by a literal value, a `${env.VAR}` / `${var.api_key}` placeholder, or
the `auth.env` sugar (an env var name). `auth.env` fills the primary credential —
header/query `value`, basic `password`, or OAuth2 `client_secret`; other OAuth2
slots (`client_id`, `token_url`) use a literal or a `${env.VAR}` placeholder. An
env-backed credential that is unset/empty at Configure is a hard error — never a
blank credential on the wire.

```yaml
# header (the conventional case)
auth: { type: header, header: Authorization, value: "Bearer ${env.GITHUB_TOKEN}", failure_status: [401] }

# query — secret in the URL query (least-safe; use only when the API mandates it)
auth: { type: query, param: api_key, env: NASA_API_KEY }

# basic — engine builds Authorization: Basic base64(user:pass)
auth: { type: basic, username: "${env.API_USER}", password: "${env.API_PASS}" }

# oauth2 client-credentials — token fetched at request time, cached, refreshed on 401
auth:
  type: oauth2
  oauth2:
    token_url: "https://auth.example.com/oauth/token"   # absolute HTTPS
    client_id: "${env.CLIENT_ID}"
    client_secret: "${env.CLIENT_SECRET}"               # sent client_secret_post (form body)
    scopes: [read, write]
    audience: "https://api.example.com"                 # optional
```

`failure_status` lives on `connection.auth` (any auth type) and marks statuses
surfaced as a distinct auth diagnostic instead of a generic error.

For `oauth2`, the nested `auth.oauth2` block is the canonical form; the same
`token_url`/`client_id`/`client_secret`/`scopes`/`audience` keys are also accepted
directly under `auth` as compatibility shorthand.

## schema.attributes

Each attribute declares exactly one practitioner role: `required`, `optional`, or
`computed` (an optional may also carry a `default`).

```yaml
schema:
  attributes:
    id:      { type: string, computed: true }
    name:    { type: string, required: true }
    size:    { type: number, optional: true }
    enabled: { type: bool, optional: true, default: true }
    token:   { type: string, computed: true, sensitive: true }   # mark credentials sensitive
```

Field reference:

- `type`: `string | number | bool | object | list | set | map`. A `number`
  attribute whose server value arrives as a JSON **string** (e.g. `"42"`) is
  coerced to a number on read/create, so declare such fields `number` — you do not
  need a string-typed workaround.
- `field`: API field name when it differs from the attribute name (e.g. attribute
  `value` ↔ API field `count`, or computed attribute `run_id` ↔ response field
  `id`). Defaults to the attribute name. This mapping is the **projection**: on
  every read/create/action response the engine reads each declared attribute from
  its `field` in the response body and stores it under the attribute name. Fields
  in the response that no attribute claims are simply ignored (you don't need to
  list them); `ignore_server_fields` only matters for fields you'd otherwise model
  but want stripped to avoid a diff. So to surface a computed output, declare an
  attribute with `computed: true` and (if names differ) `field:` — that is the
  whole mechanism, for resources, data sources, ephemerals, and actions alike.
- `sensitive`: keep out of plan/CLI output. **Required on any credential-bearing
  attribute** — the transport redactor cannot reach attribute values.
- `default`: a literal default for an `optional` attribute. **`string`, `number`,
  and `bool` defaults are all accepted** (collections/objects are not). **Prefer
  `default:` to absorb a stable, server-supplied default** — e.g. a server-defaulted
  `retries: 3`, `job_type: "run"`, `verbosity: 0`. A static default keeps the unset
  value **plan-known** (not `(known after apply)`) **and preserves drift detection**,
  which is strictly better than `optional + computed` for any field whose server
  default is a known scalar literal (including `0` / `false` / `""`):

  ```yaml
  # server defaults retries→3 when omitted; pin it so the plan knows the value
  # AND Terraform still detects a remote drift away from 3:
  retries: { type: number, optional: true, default: 3 }
  ```

  Use `optional: true, computed: true` (no `default`) **only** when the server's
  default is *not* a pinnable scalar — a canonicalized form of your input, or an
  object/list/variable/environment-dependent value — where there is no stable
  literal to declare. `computed` is apply-safe but **drift-blind** on the unset
  field, so reserve it for that case.

  Marking a server-defaulted field plain `optional` (no `default`, no `computed`)
  causes a "Provider produced inconsistent result after apply" error on first apply.
  The `optional_default_consistency` conform invariant catches this **offline**
  (auto-selected for create-lifecycle resources): if the recorded create omits the
  field but the response returns it non-null, `conform` fails — fix it by declaring
  `default: <the server's literal>` (preferred) or `optional + computed`. A declared
  `default:` must match the omitted-create response value, so the invariant also
  rejects a declared default that conflicts with the recorded evidence.

  **YAML shape ≠ generated schema.** A declared `default:` forces the generated
  terraform-plugin-framework attribute to optional+computed+default (the framework
  requires a default to be computed). Keep `computed:` **absent** in the contract
  YAML anyway: `optional_default_consistency` keys on the `optional`-not-`computed`
  attributes, and the drift-detection advantage comes from the default being a
  plan-known literal — not from the absence of the `computed:` key.
- `description`: human-readable attribute description (surfaced in the generated schema).
- `carry_on_read`: preserve an **optional, non-computed** input in state when a
  read omits it (the server accepts but doesn't echo it) — prevents a perpetual
  diff. Invalid on required/computed attributes.
- `normalize`: `lowercase` (string) or `sort` (list/set) — store the server's
  normalized form so a server-normalized value doesn't churn. Applied after
  `carry_on_read`. Type-mismatched directives are rejected at load.

Collections and nesting:

```yaml
data:   { type: object, fields: { price: { type: number }, sku: { type: string } } }
ports:  { type: list, element: { type: number } }
tags:   { type: set, element: { type: string } }
rates:  { type: map, value_type: number }            # string→number map
items:  { type: list, element: { type: object, fields: { id: { type: string } } } }  # list of objects
```

## identity (resources)

```yaml
identity:
  attribute: id              # which schema attribute holds the id
  response_field: _id        # OPTIONAL — only when the API returns the id under a
                             # different field. Defaults to the identity attribute's
                             # field, so omit it when they match (the common case).
  known_after: create        # optional, informational (bootstrap emits "create")
```

An identity used verbatim in URLs should be `type: string` — Terraform stores
numbers as arbitrary-precision floats, so a non-canonical token (`007`, `1e6`,
`1.0`) is canonicalized on the state round-trip and the rebuilt URL won't match.

This `type: string` rule is about the **identity**. A `type: number` attribute used
as a foreign key or input — `team_id`, `project_id`, `pipeline_id` — *does*
interpolate cleanly into `${...}` paths and bodies: a canonical integer id renders
without float artifacts (`7`, not `7.0`). So model integer FK ids as `type: number`
and reference them in paths (`/pipelines/${pipeline_id}/runs/`) and bodies
freely. Only switch the identity itself to `type: string` for non-canonical tokens.

## lifecycle

CRUD for resources; `open`/`renew`/`close` (+ `renew_after_seconds`) for
ephemeral. Each is an **operation**:

```yaml
lifecycle:
  create: { method: POST, path: /widgets, body: [name, size], expect_status: [201] }
  read:   { method: GET,  path: /widgets/${id}, not_found_status: [404] }
  update: { method: PATCH, path: /widgets/${id}, body: [name, size], refresh_after: true }
  delete: { method: DELETE, path: /widgets/${id}, expect_status: [204], not_found_status: [404] }
```

Operation fields:

- `method`, `path` (with `${id}` / `${var}` interpolation), `body` (attrs to send),
  `query` (attrs as query params — data sources), `request_content_type`.
- `expect_status` / `not_found_status`.
- `refresh_after`: re-read after a write whose response is empty/partial.
- `delete_on_create_failure`: clean up if create succeeds but refresh fails.
- Envelope unwrap: `response_path` (dotted keys/indices, e.g. `data` or
  `results.0`), `response_index` (index into a selected array),
  `response_scalar_attr` (attribute receiving a scalar/whole-value body).
- `async`: long-running operations (below).
- `pagination`: multi-page reads (below).

### ephemeral lifecycle (open/renew/close)

A `kind: Ephemeral` contract uses `open`/`renew`/`close` instead of CRUD. `open`
exchanges inputs for a short-lived value (the computed, usually `sensitive`,
outputs); `renew` extends the lease; `close` revokes it. `renew_after_seconds`
tells Terraform when to renew. It has no `identity`. Proven with
`ephemeral_open_renew_close` (which requires both `renew` and `close` declared).

```yaml
kind: Ephemeral
schema:
  attributes:
    username: { type: string, required: true }
    password: { type: string, optional: true, sensitive: true }
    token:      { type: string, computed: true, sensitive: true }
    expires_in: { type: number, computed: true }
lifecycle:
  open:  { method: POST, path: /login,   body: [username, password], expect_status: [200] }
  renew: { method: POST, path: /refresh, expect_status: [200] }
  close: { method: POST, path: /logout,  expect_status: [200, 204] }
  renew_after_seconds: 3600
conformance:
  example: { username: svc-account, password: REDACTED }   # credential values use the REDACTED sentinel
  invariants: [ephemeral_open_renew_close]
```

`bootstrap --kind ephemeral` emits this shape with **placeholder** `/renew` and
`/logout` paths — replace them with the real endpoints before recording (see
`repair-hints.md`).

### async (long-running create/update/delete)

```yaml
async:
  accepted_status: 202
  # poll target: either a JSON job id substituted into status_path...
  job_id_field: job_id
  status_path: /jobs/${job_id}
  # ...or read from a response header:
  status_from: header:Location
  status_field: status
  success_value: succeeded
  failure_values: [failed, cancelled]
  resource_field: resource     # where the materialized resource lives (not needed for delete)
  max_polls: 30
  poll_interval: 2             # seconds
  timeout_seconds: 120         # per-job deadline → distinct "expired" diagnostic
```

Async applies to create, update, and delete. A delete polls to terminal and
treats the read's `not_found_status` as success (deletion done).

### pagination (multi-page reads)

```yaml
pagination:
  style: cursor                # cursor | link-header | offset | page
  items_path: data             # the array to concatenate across pages
  next_field: next_cursor      # cursor style
  has_more_field: has_more     # optional
  cursor_param: cursor
  offset_param: offset         # offset style
  page_param: page             # page style
  page_size_param: per_page
  page_size: 100
  start_page: 1                # page style: first page index
  zero_indexed: false          # page style: 0-indexed APIs
  max_pages: 20
```

The assembled list projects onto a single list/set attribute. Page-metadata
scalars (e.g. a `total_count` attribute) can be co-projected alongside the list.

## actions (custom non-CRUD verbs)

`actions` maps a verb name to a single operation, the same operation shape as a
lifecycle method:

```yaml
actions:
  start:                                  # verb name
    method: POST
    path: /pipelines/${pipeline_id}/runs/   # ${...} from input attributes
    expect_status: [201]
    # body: [parameters]    # OPTIONAL — omit entirely to send an empty POST
```

- The action's response projects onto the contract's **computed** attributes by
  the same `field:` rule as everything else — declare a computed attribute (e.g.
  `run_id` with `field: id`) to surface a value the action returns.
- **Omit `body` to send an empty request** (a bare trigger). A body is sent
  only when you list attributes in it.
- Path/body interpolate `${attr}` from the contract's input attributes.

**Action-only contracts (no CRUD).** A `kind: Resource` may declare `actions` and
**no `create` lifecycle**. The engine then registers it as a Terraform **Action**
(named `dynamic_<type>_<verb>`), not a managed resource — so it's exempt from the
CRUD invariant coverage floor and is proven with `action_returns_expected` plus
(when the action returns a server-assigned id) `state_matches_expect`, instead
of the CRUD set. This is the idiomatic way to model an imperative verb (launch
a job, rotate a key, start/stop) that creates no Terraform-managed object. See
`terraform-usage.md` for how this surfaces in HCL.

Two-pronged action proof:

- **Stable** computed outputs (`status`, `name` — values that don't change per
  invocation) go in `conformance.example`. `action_returns_expected` does a
  literal compare against the action result.
- **Server-assigned id-shaped** outputs (the new run id, the launched job id —
  values the server assigns fresh each invocation) go in
  `conformance.expect.<attr>: {not_null: true}`. `state_matches_expect`
  (now driving action contracts too, not just datasources/resources) checks
  presence without freezing the per-run value. Pinning a server-assigned id in
  `conformance.example` passes the frozen cassette but breaks the next
  re-record — `record` now warns about this at record time. `bootstrap --kind
  action` emits this split by default.

Complete action-only contract, end to end (copy this shape — there is nothing
else to it):

```yaml
apiVersion: agentprovider/v1
kind: Resource           # still Resource; the missing create lifecycle makes it an Action
type: job_run
connection:
  base_url: "${var.base_url}"
  auth: { type: header, header: Authorization, value: "Bearer ${env.API_TOKEN}" }
schema:
  attributes:
    pipeline_id: { type: number, required: true }                # input, interpolated into the path
    run_id:      { type: number, computed: true, field: id }     # computed OUTPUT (response field `id`) — server-assigned
    status:      { type: string, computed: true }                # computed output — stable
actions:
  start:
    method: POST
    path: /pipelines/${pipeline_id}/runs/
    expect_status: [201]
    # no body: an empty POST
conformance:
  action: start                        # which verb the proof drives
  example:
    pipeline_id: 7
    status: pending                    # stable: every started run begins pending — pinned literal
  expect:
    run_id: { not_null: true }         # server-assigned per run — assert presence, never pin a literal
  invariants:
    - action_returns_expected          # literal compare on the example pin (status)
    - state_matches_expect             # not_null check on the expect entry (run_id)
```

This contract registers the Terraform Action `dynamic_job_run_start`. The proof
is non-vacuous because `conformance.example` asserts a stable computed output
(`status`) AND `conformance.expect` asserts the server-assigned id is present —
an action contract with neither is vacuous and fails closed.

## conformance

```yaml
conformance:
  example:   { name: widget-a, size: 7 }      # inputs for create
  update_to: { size: 9 }                       # inputs for update
  invariants: [id_is_computed_and_nonempty, create_echoes_inputs, read_matches_create,
               update_then_read_reflects, second_apply_is_noop, delete_then_read_404,
               import_reconstructs, id_stable_across_update]   # last two are REQUIRED (see floor)
```

### conformance.expect (optional output matchers)

An optional `expect` block asserts specific output values in the final state,
proven by the `state_matches_expect` invariant. Each leaf is either an exact
literal or a single-key matcher map; nested objects assert nested paths:

```yaml
conformance:
  example: { name: widget-a, size: 7 }
  expect:
    id:       { not_null: true }          # present and non-empty
    name:     { matches: "^widget-" }     # regex over the stringified value
    size:     { number_approx: { value: 7, tol: 0.5 } }   # numeric ±tol
    obsolete: { absent: true }            # nil / missing
    data:     { sku: WIDGET-A }           # nested path, exact literal
  invariants: [state_matches_expect]
```

**Required-invariant coverage floor.** For an id-keyed resource that has both
`read` and `update`, the engine *requires* `import_reconstructs` and
`id_stable_across_update` in addition to the CRUD set — `conform` fails closed
until they're declared. Include them from the start on every full-CRUD resource;
don't wait for the first conform to tell you.

A contract must declare the invariants it wants — the harness fails closed on
zero checks. See `repair-hints.md` for the full invariant catalog and which apply
to which contract shape.
