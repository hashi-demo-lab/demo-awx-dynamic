# Invariants and repair hints

`agentprovider conform` runs the invariants a contract **declares** under
`conformance.invariants` and emits a ranked `repair_hints` list on failure. This
catalog explains each standard invariant and the common symptom → fix → *why* so
you can apply a hint with understanding, not by rote.

## The standard invariant set

Pick the ones that fit the contract shape; the harness fails closed if you declare
none.

| Invariant | Proves | Applies to |
|---|---|---|
| `id_is_computed_and_nonempty` | the resource gets a non-empty server id | resources |
| `create_echoes_inputs` | create response reflects the inputs sent | resources |
| `read_matches_create` | a read after create returns the same state | resources |
| `update_then_read_reflects` | an update is visible on the next read | resources with update |
| `second_apply_is_noop` | re-applying identical config plans nothing (no perpetual diff) | resources; drift contracts |
| `optional_default_consistency` | no `optional` (non-`computed`) attribute is one the server defaults when omitted — the offline guard against Terraform's "inconsistent result after apply" (null→default) | **auto-selected** for any resource with a `create` lifecycle |
| `delete_then_read_404` | after delete, a read is not-found | resources with delete |
| `nested_object_preserved` | a nested object round-trips through create/read | contracts with object attributes |
| `server_fields_ignored` | `ignore_server_fields` entries don't cause a diff | contracts with server-injected fields |
| `unexpected_status_errors` | an unexpected status surfaces a clear error (not silent) | any contract (negative) |
| `auth_failure_surfaced` | a 401/403 surfaces as a distinct auth diagnostic | auth contracts (negative) |
| `auth_token_refreshed_on_401` | an OAuth2 401 triggers exactly one refresh then succeeds | oauth2 contracts |
| `redirect_followed_to_resource` | an async Location-redirect poll reaches the resource | async 303-redirect |
| `job_expiry_surfaced` | an async job past its deadline surfaces a distinct expiry error | async job-expiry |
| `async_update_polls_to_terminal` | an async update polls to terminal and reflects new state | async update |
| `async_delete_polls_to_gone` | an async delete polls to terminal then reads not-found | async delete |
| `action_increment_changes_count` / `action_decrement_changes_count` | a custom action mutates state | action contracts (counter) |
| `read_returns_expected` | a read projects the expected computed outputs (drives `read`, no create) | data sources / read-only contracts |
| `state_matches_expect` | the final state matches the `conformance.expect` matcher block (`not_null`/`matches`/`number_approx`/`absent`, nested paths) | any contract declaring `conformance.expect` |
| `ephemeral_open_renew_close` | open→renew→close lifecycle; open returns the computed outputs, renew + close succeed | ephemeral resources (requires `lifecycle.renew` **and** `lifecycle.close`) |
| `import_reconstructs` | `terraform import` seeds the id and a read rebuilds state | **required** for id-keyed resources with read+update |
| `id_stable_across_update` | the identity value is unchanged from create through update | **required** for id-keyed resources with read+update |

**Required coverage floor.** The last two above are not optional for a full-CRUD
resource: an id-keyed resource with both `read` and `update` *must* declare
`import_reconstructs` and `id_stable_across_update` or `conform` fails closed.
Declare them from the start alongside the CRUD set.

## What each invariant actually compares

Here's the comparison each check runs, so you can predict a pass/fail before
recording. All comparisons run **after projection** (the `field:` mapping) and
**after `ignore_server_fields`** are stripped, so server timestamps and remapped
fields
don't trip them.

- `id_is_computed_and_nonempty` — after `create`, the identity attribute
  (`identity.attribute`, populated from `identity.response_field`) is present and
  non-empty.
- `create_echoes_inputs` — every input you sent in `conformance.example` appears
  with the same value in the **create response** (the server echoed what you sent).
  Inputs the server doesn't echo aren't checked here.
- `read_matches_create` — the state after a `read` equals the state after `create`,
  attribute by attribute. This is where a perpetual-diff field shows up (fix with
  `refresh_after`, `carry_on_read`, `normalize`, or `ignore_server_fields`).
- `update_then_read_reflects` — after applying `update_to`, a `read` returns the
  updated values. Requires `update_to` to list the **full** body (see the catalog).
- `second_apply_is_noop` — re-projecting the read state against the config produces
  no diff (no churn on a second apply).
- `optional_default_consistency` — a **static** check (no engine drive): for every
  attribute declared `optional` and **not** `computed`, it inspects the recorded
  **create** request/response pair. If the field was omitted from the create body
  but came back non-null in the response, the server defaults it — and Terraform
  will reject the null→default at apply ("inconsistent result after apply"). Fix
  (two branches): if the omitted-create response is a **stable scalar literal**,
  declare `optional: true, default: <that literal>` (preferred — plan-known and
  drift-detecting; the declared default must equal the recorded value); otherwise,
  for a non-pinnable default (object/list, canonicalized, variable), declare
  `optional: true, computed: true`. Auto-selected for any create-lifecycle resource,
  so it catches the bug **offline**, before a real apply. (Keys on the create
  interaction only; update-omit defaults are out of scope.)
- `id_stable_across_update` — the identity value is unchanged from create through
  update (Terraform's identity-stability expectation).
- `delete_then_read_404` — after `delete`, a `read` returns a `not_found_status`.
- `action_returns_expected` — after running `conformance.action`, the action's
  response projects the computed outputs named in `conformance.example` (so put a
  real expected computed value there — `run_id: 29` — not just the inputs).
- `read_returns_expected` — drives `read` directly (no create) and checks the
  computed outputs in `conformance.example` are projected.
- `state_matches_expect` — walks the `conformance.expect` tree against the final
  state. Each leaf is either an exact literal or a single-key matcher map:
  `{not_null: true}` (present and non-empty), `{matches: "<regex>"}`,
  `{number_approx: {value: <n>, tol: <n>}}`, or `{absent: true}` (nil/missing).
  Nested objects assert nested paths.

## Repair-hint catalog (symptom → fix → why)

- **id is empty / missing after create** → set `identity.response_field` to the
  field the API actually returns the id in (e.g. `_id`, `node_id`). *Why:* the
  server returns the id under a non-conventional key; the engine maps
  `response_field` → `identity.attribute`.
- **`second_apply_is_noop` fails after an empty/partial write response** → add
  `refresh_after: true` to the write op. *Why:* the write returned no/partial body,
  so state is incomplete; a follow-up read fills it and stops the diff.
- **perpetual diff on a server-injected field (createdAt/updatedAt/etag)** → add the
  field to `ignore_server_fields`. *Why:* the server mutates it every read; stripping
  it keeps state stable. (`record --suggest` proposes these.)
- **perpetual diff on an optional input the read omits** → set `carry_on_read: true`
  on that optional attribute. *Why:* the API accepts but doesn't echo it; carrying
  the practitioner value forward avoids a null-vs-set diff.
- **`optional_default_consistency` fails, or `completeness` emits a
  `promote_schema_attribute` hint ("set default:&lt;v&gt; on &lt;path&gt; to keep it
  plan-known and preserve drift detection") on a server-defaulted optional** → add
  `default: <that scalar literal>` to the existing optional attribute (do **not** add
  `computed:`); for a non-pinnable default (object/list, canonicalized, variable) use
  `optional: true, computed: true` instead. *Why:* a static `default:` keeps the unset
  value plan-known **and** preserves drift detection, where `computed` is drift-blind;
  the CLI sources the literal from the recorded omit-create response, so it matches
  what the conform gate validates.
- **perpetual diff on a server-normalized value (lowercased email, sorted list)** →
  set `normalize: lowercase` / `normalize: sort` on the attribute. *Why:* store the
  server's normalized form so the planned and actual values match.
- **conform/replay mismatch on a string the server canonicalizes (trailing newline
  trimmed, whitespace collapsed)** → set the `conformance.example` (and `update_to`)
  value to the *server-returned* form, not your raw input — e.g. drop the trailing
  `\n` the server strips from a multi-line `extra_vars`/`variables` string. *Why:*
  the recorded response holds the canonicalized value, so an example carrying the
  un-canonical form won't match on replay. `normalize` covers case/sort, not
  whitespace — align the example to what the server actually returns.
- **wrong status error on create/read** → fix `expect_status` / `not_found_status`
  to the codes the API actually returns (e.g. create returns 200 not 201). *Why:*
  the engine gates on declared statuses.
- **PUT/PATCH mismatch / fields not updating** → set `update.method` to what the API
  uses, and list the changeable attributes in `update.body`.
- **auth failure not distinct** → add `failure_status: [401, 403]` to header auth (or
  use `auth.type: oauth2` for token refresh). *Why:* surfaces a clear auth diagnostic
  instead of a generic status error.
- **envelope: fields are nested under `data`/`results`** → set `response_path` (e.g.
  `data`, `results.0`) and/or `response_index`. *Why:* unwraps the envelope before
  projection onto flat attributes.
- **list response not assembling across pages** → add a `pagination` block matching
  the API's style (cursor/link-header/offset/page) with `items_path`. *Why:* the
  engine follows pages and concatenates `items_path` arrays.
- **async create times out / never materializes** → add an `async` block
  (`accepted_status`, poll target via `job_id_field`+`status_path` or
  `status_from: header:Location`, `status_field`, `success_value`, `resource_field`).
- **load error: a field is in both `schema.attributes` and `ignore_server_fields`**
  → pick one. A server-only field you want stripped (createdAt/updatedAt) goes in
  `ignore_server_fields` and is **not** declared as a schema attribute; a field you
  model as state is a schema attribute and must not also be ignored. *Why:* the two
  lists are disjoint — one projects the field into state, the other strips it.
- **request doesn't match the recording / `${id}` shows up un-substituted** → use the
  `${...}` placeholder form in paths (`/widgets/${id}`) and async `status_path`
  (`${job_id}`). *Why:* the engine interpolates only `${...}`; a bare `{id}` is a
  literal, so the built URL never matches the recorded request.
- **invariants fail with `expected status in [], got 200`** → declare `expect_status`
  on the operation that returned it (e.g. `read: { expect_status: [200] }`). *Why:*
  the engine gates strictly with no default-accept. The auto hint may point at
  `create.body`/`refresh_after` here — that is misattributed; the real fix is the
  missing status on the op named in the failing result's `actual`.
- **`update_then_read_reflects` fails after a partial change / update body mismatches
  the recording** → put the *full* desired object in `update_to` (and list all
  changeable keys in `update.body`), not just the changed field. *Why:* the engine
  builds the request body only from keys present in the config map, so a partial
  `update_to` produces a body that won't match the recorded request signature.
- **load error: "attribute is a reserved Terraform root argument"** → rename the
  attribute and map it to the API key with `field:` (e.g. attribute `value` with
  `field: count`). *Why:* `count` and the other HCL meta-args are reserved at the
  resource root and cannot be attribute names.
- **a `kind: DataSource` can't make any invariant pass** → declare
  `read_returns_expected`, which drives `read` directly, and put the read inputs
  *plus* at least one real expected computed output in `conformance.example`. *Why:*
  it fails closed if no computed output is verified, so a null/empty example proves
  nothing. (The old create=read mirror still works but is no longer necessary.)
- **bootstrapped ephemeral: `ephemeral_open_renew_close` fails on a fresh draft** →
  `bootstrap --kind ephemeral` writes **placeholder** `lifecycle.renew.path` (`/renew`)
  and `lifecycle.close.path` (`/logout`). Replace both with the real API endpoints
  *before* recording, then re-record. *Why:* the seed is a starting point; the
  invariant runs open→renew→close, and placeholder paths won't match the recorded
  cassette (or will 404 live). A `--response`-seeded ephemeral also has an empty
  `open.body` — add at least one real input attribute before recording.
- **bootstrapped action: `action_returns_expected` fails with actual ≠ `PLACEHOLDER`**
  → `bootstrap --kind action` seeds **stable** computed outputs in
  `conformance.example` with a literal `PLACEHOLDER` (or `0`/`false`). After
  recording, read the cassette response and replace each placeholder with the
  real value the action returns (status, name, anything that doesn't change per
  run), then re-run `conform`. *Why:* the seed declares the proof's *shape*; the
  invariant compares the example value against the recorded response, so a
  placeholder fails closed until you supply the true value. Server-assigned
  id-shaped outputs are already routed into `conformance.expect.<attr>: {not_null:
  true}` — leave them there, don't move them into `example`. `action_returns_expected`
  proves output projection only — for a state-changing verb, add an effect
  invariant too (the counter `action_*_changes_*` pattern).
- **`record` warning: `conformance.example pins X but the live run observed Y`** →
  move `X` out of `conformance.example` and into `conformance.expect.X: {not_null:
  true}`, then make sure `state_matches_expect` is in the contract's `invariants`
  list. *Why:* the pinned value is server-assigned and changes each invocation;
  pinning it as a literal makes `conform` pass against the frozen cassette but
  fail the moment the cassette is re-recorded. The `not_null` matcher asserts
  presence without freezing the value, and `state_matches_expect` (now driving
  action contracts too) is the invariant that walks `expect`. `bootstrap --kind
  action` emits this shape by default for id-shaped outputs; the warning catches
  hand-written contracts that bypass the bootstrap default. The warning is
  non-fatal — exit 0, recorded cassette is still written — but ignoring it sets
  up the next re-record to fail.
- **contract won't load (validation error)** → fix the named key/shape; this is the
  *cannot-express* path, not a fixable invariant failure. If the API genuinely needs
  something the format lacks, stop and report the engine gap rather than weakening
  the contract to make a check pass.

## Don't green-wash

A passing run with no invariants, or one where you removed/weakened an invariant
until it passed, is not proof. If a real capability is missing (auth not actually
exercised, a shape the format can't express), that's a genuine gap to surface — not
something to hide behind a green `overall_passed`.

`conform --mutation-check --emit-proof` must also pass with targeted evidence.
The mutation check does not accept ignored metadata or arbitrary fallback scalar
changes as proof: it must kill `conform` by mutating an asserted output,
`conformance.expect` leaf, identity response field, mapped schema field, or
status-sensitive invariant response. If it reports inconclusive, add a real
assertion surface and re-record/re-run; do not delete the invariant to make the
proof sidecar appear.
