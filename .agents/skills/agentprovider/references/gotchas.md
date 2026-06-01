# Gotcha catalog — the worked detail behind SKILL.md's loop-burner table

These burn the most `conform`/`record` loops. SKILL.md lists the one-liners; this
is the *why* and the fix. `references/repair-hints.md` maps failure symptom → fix.

- **Plaintext `http://` or private/loopback target needs both `allow_insecure` and
  `allow_private_host` under `connection`.** Otherwise the transport/SSRF guard
  rejects the host at `record`/`plan` time. Public HTTPS APIs need neither.

- **`auth` nests under `connection` (not top-level)** — a top-level `auth` block is
  the most common first-`validate` failure. Canonical shape:
  ```yaml
  connection:
    base_url: ${env.API_BASE_URL}   # ORIGIN only; full /api/v2/... lives in each op path
    allow_insecure: true             # reviewed http:// only
    allow_private_host: true         # reviewed loopback/private only
    auth: { type: basic, username: ${env.API_USERNAME}, password: ${env.API_PASSWORD} }
  ```

- **`connection.base_url` must resolve at RUNTIME** (`${env.VAR}` or provider config,
  never an undefined `${var.*}`). `conform` does **not** exercise `base_url` (replay
  matches op `path` literally; `record` overrides the host with `--base-url`), so a
  bogus value passes every invariant and only fails at `terraform apply` with
  `unsupported protocol scheme ""`. Keep it identical across every contract.

- **Paths interpolate `${...}`, never `{...}`** — `path: /widgets/${id}`. A bare
  `{id}` is a literal and won't match the recording.

- **Every operation declares its happy-path `expect_status`** — no default-accept,
  so even a 200 read needs `expect_status: [200]`. On `expected status in [], got
  200`, add the status to the op named in the failing result (the auto-hint may
  misattribute it to `create.body`).

- **`update_to` and `update.body` must list the same request-body keys — both
  ways.** `record` sends every `update.body` attribute on the live PATCH (a modeled
  optional is sent even as `null`), but `conform` rebuilds the request from
  `update_to`'s keys — so a key in `update.body` that `update_to` omits makes the
  replayed body shorter → byte-replay miss (`no recorded interaction for PATCH …`).
  If a field is never changed, drop it from `update.body`; if it is, give it a value
  in `update_to`. Keep the two key sets identical.

- **The `example` must match the request the recorder replays — re-record after you
  change a *replayed* value.** An `optional+computed` field the server defaults is
  still sent, so it must appear in `example`/`update_to` with the server's value; a
  value the server canonicalizes (trims newline, lowercases) must be written in its
  returned form. Re-record only when you change what is **replayed as a request**
  (an `example`/`update_to` input that lands in a body/path, or an op `body`).
  Editing a pure **assertion target** (an action's expected output, a
  `conformance.expect` matcher) needs **no** re-record.

- **Reserved Terraform meta-args (`count`, …) can't be attribute names** — expose the
  API field under another name with `field:` (attribute `value`, `field: count`).

- **Object/nested attributes need an explicit `required`/`optional`/`computed` marker**,
  including fields *inside* an object.

- **Pick the attribute shape by what the server does when the field is OMITTED.**
  Reflexively marking every optional `computed` loses drift detection on real inputs.
  - **Rejects omission** → `required`.
  - **Returns null/absent** (confirmed unset) → `optional` (plain). Drift-detecting.
  - **Returns a stable scalar literal** (incl. `""`/`0`/`false`/`"run"`) →
    `optional: true, default: <literal>` (no `computed:` key). **Preferred** —
    plan-known *and* drift-detecting. The CLI auto-suggests for meaningful scalars
    (`"run"`,`1`,`3`); for `0`/`false`/`""` it stays silent, so you declare `default:`.
  - **Returns a non-pinnable default** (object/list/map, canonicalized input, env-dependent)
    → `optional: true, computed: true`. Apply-safe but drift-blind.
  - **Pure server output** (never settable) → `computed` only.
  - A server that echoes any value on omit (even `0`/`false`/`""`) is server-defaulting —
    never leave it plain `optional` (re-introduces "inconsistent result after apply").
  - **YAML shape ≠ generated schema:** a declared `default:` makes the *generated*
    attribute optional+computed+default, so keep `computed:` **absent** in the YAML —
    `optional_default_consistency` checks exactly the `optional`-not-`computed` attrs.
  See `references/contract-format.md` (`default:`) for the worked example.

- **An action input must not map to the same API field as a computed output.** A
  by-id action interpolating `${id}` while a computed output already maps `field: id`
  makes two attributes claim API field `id` → load failure (`… both map to API field
  "id"`), surfacing only at record/replay. Name by-id inputs distinctly
  (`template_id`, `pipeline_id`).

- **`bootstrap --kind action` is action-only but still a draft** — `kind: Resource`
  with an `actions:` block, no `identity`/`lifecycle`. Set the real action path and
  replace placeholder computed outputs before `conform`.

- **Custom-action invariants are name-keyed** — `action_increment_changes_count` /
  `action_decrement_changes_count` drive actions named exactly `increment`/`decrement`.

- **Choose an action's `type` so `<type>_<verb>` equals the Terraform action id.** The
  action surfaces as `dynamic_<type>_<verb>` by concatenation. For `task_launch`, set
  `type: task` + verb `launch` — **not** `type: task_launch` (→ `dynamic_task_launch_launch`
  and a plan-time "no action schema" error). `validate`/`preflight` warn when `type`
  ends in a declared verb; heed the advisory (the contract still loads).

- **Action contracts need a real computed output check** — declare
  `action_returns_expected` with ≥1 computed response field in `conformance.example`
  (e.g. `run_id`). A config-only action proof is vacuous and should fail closed.

- **`field:` projects explicit dotted response paths, not arbitrary reshaping.**
  `job_id: { field: id }`, `group_name: { field: summary.groups.name }` work.
  Projection reads the raw response before ignored parents are stripped, so a modeled
  leaf under `summary` can coexist with `ignore_server_fields: [summary]`. Object keys
  and numeric array segments only; arbitrary list reshaping is a separate problem.

- **An identity used verbatim in URLs should be `type: string`.** Terraform stores
  numbers as floats, so a non-canonical token (`007`, `1e6`, `1.0`) is canonicalized
  and the rebuilt URL won't match. `conform` enforces this with a "declare type:
  string" hint. Integer FK ids may stay `type: number` only for canonical integer
  path segments.
