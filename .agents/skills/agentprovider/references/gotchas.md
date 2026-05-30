# Get these right up front — the gotcha catalog

These burn the most `conform` loops. Fix them at authoring time rather than
discovering them one failed run at a time. `references/repair-hints.md` carries the
symptom→fix mapping and the *why* for each. SKILL.md lists the one-line versions;
this file is the detail.

- **A plaintext-`http://` or private/loopback target needs both `allow_insecure`
  and `allow_private_host` in `connection`** — set them up front for a local/dev or
  internal API (e.g. `http://localhost:...`, a `10.`/`192.168.` host). Otherwise the
  engine's transport/SSRF guard rejects the host and you only discover it at
  `record`/`plan` time. The skill's other examples assume a public HTTPS API, where
  neither is needed.

- **`auth` nests UNDER `connection`, and `connection.base_url` must resolve at
  RUNTIME.** Two recurring, cheap-to-avoid taxes. (1) `auth` is a child of
  `connection` (alongside `base_url`/`headers`), not a top-level key — a top-level
  `auth` block is the single most common first-`validate` failure, and a
  bootstrap/hand-authored draft is exactly where it creeps in; place it right the
  first time. The canonical shape:
  ```yaml
  connection:
    base_url: ${env.AWX}          # ORIGIN only; full /api/v2/... lives in each op path
    allow_insecure: true           # only for reviewed http:// targets
    allow_private_host: true       # only for reviewed loopback/private hosts
    auth: { type: basic, username: ${env.AWX_USERNAME}, password: ${env.AWX_PASSWORD} }
  ```
  (2) `connection.base_url` must point at something that resolves when Terraform
  runs — `${env.VAR}` or provider config, **never an undefined `${var.*}`**. This is
  insidious because **`conform` does not exercise `base_url`** (cassette replay
  matches op `path` literally and `record` overrides the host with `--base-url`), so
  a bogus `base_url` passes every invariant and only fails at `terraform apply` with
  `unsupported protocol scheme ""`. Set it to the same runtime-resolvable origin you
  record against, and keep it identical across every contract in the provider.

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
  inputs distinctly — `<resource>_id` (`template_id`, `pipeline_id`).

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
  `validate` and `preflight` emit a non-fatal advisory when `type` ends in a
  declared verb (naming the doubled id and the split fix), so you catch this before
  recording — but the contract still loads, so heed the advisory.

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
