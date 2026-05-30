# agentprovider CLI authoring loop

All commands below use the `agentprovider` CLI; make sure it's available on your
PATH before you start. The core authoring subcommands are `bootstrap`, `schema`,
`invariants`, `validate`, `describe`, `introspect`, `preflight`, `record`, and
`conform`, with `completeness` (coverage gate) and `refresh` (drift gate) alongside; serving an
already-authored provider is separate (see `docs/RUNNING.md`).

Run `agentprovider help` for the command listing, and `agentprovider help <command>`
(or `agentprovider <command> -h`) for a command's flags.

## Output format

Most authoring subcommands emit JSON on stdout **by default** — this is what the
loop reads. Pass `--format text` for human-readable output where the command
supports it; `--json` is still accepted as an alias for `--format json` (the
alias always forces JSON). `schema` is a deliberate exception: it emits the
contract-file schema as `--format json` or `--format yaml`, with no text mode.
`introspect` is the other deliberate exception: it defaults to text for humans,
and supports `--json` / `--format json` for agents and scripts.

On a **runtime** fatal error (exit 1) in JSON mode, a command prints a structured
envelope to stdout. Some commands add `next_action`, `suggestions[]`, and `retry`
diagnostics; these are reviewable authoring hints, not proof readiness:

```json
{
  "command": "record",
  "ok": false,
  "error": "load contract: ...",
  "next_action": "repair the contract, cassette, credentials, schema, or invocation; do not wait-and-retry this authoring defect",
  "retry": {
    "category": "validation_error",
    "eligible": false,
    "terminal": true,
    "next_action": "repair the contract, cassette, credentials, schema, or invocation; do not wait-and-retry this authoring defect"
  }
}
```

`conform` instead folds contract load/validation failures into its `results[]`
stream as a `contract_validation` entry, so there is one parse path for all of its
failures. **Usage / flag errors** (missing arguments, an unknown flag, an invalid
`--format` value) are reported as a usage line on **stderr** with exit code **2**,
following the usual CLI convention — branch on the exit code (2 = bad invocation,
1 = runtime failure, 0 = success).

## schema / invariants / validate / describe — authoring introspection

Use these before reading Go source:

```bash
agentprovider schema --format json
agentprovider schema --format yaml
agentprovider invariants --kind resource
agentprovider invariants contracts/widget.yaml
agentprovider validate contracts/widget.yaml
agentprovider describe 'schema.attributes.<name>.default'
agentprovider describe conformance.invariants
```

- `schema` emits the whole contract-file JSON Schema. Use `--format json`
  (default) for editor/agent validation, or `--format yaml` for the same schema
  as YAML. It validates document shape, not semantic cross-field rules.
- `invariants --kind ...` returns catalog and conditional guidance; `invariants
  <contract.yaml>` returns the concrete required floor, recommended standard
  invariants, and missing entries for that contract.
- `validate` runs the same strict decode and validation path as record/conform,
  but as a standalone structured check.
- `describe <field-path>` returns authoring help for one field path. Quote
  placeholder paths such as `'schema.attributes.<name>.default'` in shells.

## preflight — readiness check

```bash
agentprovider preflight contracts/widget.yaml --stage record --base-url "$BASE_URL"
agentprovider preflight contracts/widget.yaml .agentprovider/cassettes/widget.cassette.yaml --stage proof --mutation-check
```

Preflight emits `ready`, `stage`, `blockers[]`, `warnings[]`,
`expectations[]`, and `next[]` as JSON by default. It predicts blockers before
record, conform, completeness, or proof, but it does not mutate contracts and it
does not add hidden gates to other commands.

## bootstrap — seed a draft contract

```
agentprovider bootstrap (--openapi <spec.yaml|json> [--operation <opId> | --path <p> --method <m>]
                   | --response <file.json|-> [--type <name>]
                   [--kind resource|datasource|ephemeral|action] [--action <verb>])
                   [--alias <param>=<attribute>]... [--ignore <name>]...
                   [--type <name>] [--out <path>] [--format json|text] [--json]
```

- `--openapi <spec>`: OpenAPI v3 spec; pick the resource anchor with `--operation`
  (operationId) or `--path` + `--method`.
- `--response <file|->`: infer from one example JSON response (`-` = stdin).
- `--type`: contract type name (default inferred). `--out`: defaults to
  `.agentprovider/contracts/<type>.yaml`.
- `--kind`: `resource` (default), `datasource`, `ephemeral`, or `action`.
  - `ephemeral` → a `kind: Ephemeral` draft with `lifecycle.open`/`renew`/`close`
    and the `ephemeral_open_renew_close` invariant. From `--openapi`, request-body
    fields become optional inputs and response fields become computed outputs; from
    `--response` every field is a computed output and `open.body` is empty.
  - `action` → an action-only `kind: Resource` draft (an `actions:` block + a no-op
    read, **no** create/update/delete) declaring `action_returns_expected`.
- `--action <verb>`: names the action verb for `--kind action` (default derived from
  the operationId/path, falling back to `invoke`). Only valid with `--kind action`.
- `--alias <param>=<attribute>` (repeatable): map a path parameter onto a contract
  attribute, overriding identity auto-detection (e.g. `--alias petId=id` so
  `/pets/{petId}` renders `${id}`). A malformed value (no `=`) is a usage error.
- `--ignore <name>` (repeatable): drop a schema attribute from the generated
  contract and its request bodies. Supports a dot-path for a nested field
  (`category.id` removes `id` inside the `category` object); a missing name is a
  silent no-op. Handy for pagination/query noise (`--ignore page --ignore limit`).
- From `--openapi`, the importer also infers what the spec states directly:
  `format: password` and credential-named fields become `sensitive: true`
  (recursively, including list/map element objects); a `default` is carried for
  non-sensitive string/bool attributes only (other-typed or sensitive defaults are
  dropped with a one-line stderr notice, so a secret is never written into the
  contract); and for a single-path-parameter by-id read the identity attribute is
  auto-detected and the read/update/delete path token is rewritten to it.
- The output self-validates under strict decoding before it's written, so a draft
  always loads. Treat it as a starting point to repair — and note that the new
  kinds are valid but **not yet conforming**: ephemeral drafts carry placeholder
  `renew`/`close` paths and action drafts carry placeholder `conformance.example`
  output values you must replace before `conform` passes (see `repair-hints.md`).

JSON shape (default):

```json
{
  "command": "bootstrap",
  "ok": true,
  "contract": ".agentprovider/contracts/widget.yaml",
  "type": "widget",
  "next": [
    "agentprovider record .agentprovider/contracts/widget.yaml --base-url <real-api-base-url> --out .agentprovider/cassettes/widget.cassette --suggest",
    "agentprovider conform .agentprovider/contracts/widget.yaml .agentprovider/cassettes/widget.cassette.yaml"
  ]
}
```

## introspect — discover live settable fields before authoring

```
agentprovider introspect <endpoint> --base-url <url>
               [--auth-env <VAR>] [--allow-insecure] [--allow-private-host]
               [--format json|text] [--json]
```

- `endpoint` must be a relative API path. Absolute URLs are rejected so credentials
  cannot bypass the reviewed `--base-url`.
- `--auth-env` takes the name of an environment variable containing a bearer token;
  the token value is never passed on the command line.
- Use `--allow-private-host` only for reviewed local/dev private hosts. Use
  `--allow-insecure` only for reviewed credentialed `http://` targets; the normal
  credentialed path should be HTTPS.
- The command tries read-only `OPTIONS` first and parses DRF `actions.POST` /
  update metadata into field suggestions. If `OPTIONS` is unavailable, it performs
  one sample `GET` and marks the result `confidence: reduced`.
- Reduced-confidence JSON may include `degradation`. `reason:
  insufficient_scope_or_permission` means metadata was likely auth/scope-gated;
  review credentials once instead of looping the same introspect command. Ordinary
  metadata absence is reported as `metadata_unavailable` with low confidence.
- `--auth-env` is **bearer-only**; for a basic-auth API mint a token first. Use a
  **write-scoped** token: DRF APIs (AWX/AAP) only return the `actions.POST`
  descriptor on `OPTIONS` to a principal with add permission, so a read-only token
  silently yields `source: sample, confidence: reduced`. Re-mint with write scope
  to get `source: options, confidence: high`.
- High-confidence `OPTIONS` rows may include copyable attribute snippets for
  `required`, `optional+default`, `optional+computed`, or `computed` fields.
  Sample-derived rows, nested paths, unknown requiredness, and malformed boolean
  metadata are review-only and intentionally omit a copyable `attribute`.
- It writes no files. Use it to guide bootstrapping and first-pass contract
  authoring before `preflight` / `record`; if `completeness --metadata` or proof
  emission needs a reusable DRF metadata file, save the reviewed full `OPTIONS`
  envelope, or wrap a reviewed POST map as `{"actions":{"POST":...}}`.

## record — capture a replayable cassette

```
agentprovider record <contract.yaml> --base-url <url>
               [--out <cassette-path>] [--force] [--allow-mutations] [--suggest]
               [--format json|text] [--json]
```

- `--base-url` (required): where to record against. For an unreviewed bootstrapped
  contract, use a **user-controlled staging URL**, not an embedded prod URL.
- `--allow-mutations`: permit mutating calls. Without it, resource
  create/update/delete and ephemeral renew/close are skipped (read-side only); an
  ephemeral contract's `lifecycle.open` still runs either way (it's how the
  ephemeral value is obtained).
- `--suggest`: print contract-refinement suggestions inferred from the responses,
  including legacy identity/ignore/unmodeled projections and field-level
  classification suggestions.
- `--out`: defaults to `.agentprovider/cassettes/<type>.cassette.yaml`. `--force`
  overwrites. Re-record intentionally with the same `--out` plus `--force` after
  request-shape changes; without `--force`, the JSON error carries a
  machine-readable `next_action` and `overwrite_cassette` suggestion.
- Secrets (auth headers, query secrets, OAuth2 tokens, `client_secret`) are
  redacted before the cassette is written. Review it before committing.
- The recorder refuses to persist a cassette whose recorded status is outside the
  contract's expectations (e.g. an error-shape contract must record its declared
  error status), so a bad live pass doesn't bless a wrong cassette.
- If the live run observes an asynchronous success status such as `202` or `303`
  outside the declared `expect_status`, the record still fails and writes no green
  cassette. The JSON error includes a reviewable `set_expect_status` suggestion
  naming the lifecycle/action operation and observed status; update the contract
  only if that status is truly a success for the API, then re-record with
  `--force`.
- Retry/backoff diagnostics are bounded to server-level transients: 5xx responses
  and transport timeouts. Validation errors, replay misses, schema ambiguity,
  contract status mismatches, and ordinary non-server 4xx responses are repair
  paths, not wait-and-retry paths. Mutating record operations are not retried
  automatically without an explicit idempotency guarantee.
- **Action-only contracts** (a `Resource` with `actions` and no `create`) record
  fine: `record` invokes the declared action verb against `--base-url` and captures
  the action request/response into the cassette. Pass `--allow-mutations` if the
  action mutates (e.g. a job launch). `conform` then replays it against
  `action_returns_expected`. No special flag is needed — `record` keys off the
  contract shape.

JSON shape (default). `suggestions` is present only with `--suggest`:

```json
{
  "command": "record",
  "ok": true,
  "cassette": ".agentprovider/cassettes/widget.cassette.yaml",
  "next": "agentprovider conform contracts/widget.yaml .agentprovider/cassettes/widget.cassette.yaml",
  "suggestions": {
    "identity_response_field": ["_id"],
    "ignore_server_fields": ["createdAt"],
    "server_assigned_fields": ["_id"],
    "unmodeled_fields": ["etag"],
    "field_suggestions": [
      {
        "path": "etag",
        "action": "gather_probe_evidence",
        "confidence": "medium",
        "classification": "needs_probe",
        "evidence": ["omit accepted", "non-default write accepted", "read back supplied value", "second read stable"]
      }
    ]
  }
}
```

## conform — the machine verdict (the loop driver)

```
agentprovider conform <contract.yaml> <cassette.yaml>
               [--format json|text] [--json] [--emit-proof] [--mutation-check] [--uplift]
               [--strict-freshness] [--max-cassette-age <dur>] [--reference-version <v>]
```

- `--format json|text`: output format; **`json` is the default** (what the loop
  reads). `--format text` gives the concise human verdict; `--json` is an accepted
  alias for `--format json`.
- `--uplift`: additively add any missing **standard** invariants for the contract's
  kind/lifecycle to the contract file (a byte-level splice that preserves the rest of
  the file), then conform the uplifted contract. Without `--uplift`, conform only
  **warns** on stderr about missing non-floor standard invariants (non-fatal; the
  stdout JSON verdict and exit code are unchanged). If the contract was already proven
  (a `<contract>.proven.json` exists), a passing uplift re-attests automatically and a
  failing uplift removes the stale proof — either way conform prints the complete
  `agentprovider conform <contract> <cassette> --mutation-check --emit-proof` command to reproduce it.
- `--emit-proof`: on a passing run, write a `<contract>.proven.json` attestation
  binding the proof to the contract's content hash. Proof emission requires a
  passing `--mutation-check` run and 100% completeness. New sidecars record
  `mutation_status: "passed_targeted"`; boolean-only legacy mutation sidecars
  must be regenerated before they satisfy `--require-proven`.
- `--mutation-check`: after a passing run, plan cassette mutations from
  contract-relevant obligations first: computed outputs pinned in
  `conformance.example`, `conformance.expect` leaves, identity response fields,
  `field:`-mapped schema attributes, and status-sensitive invariant responses.
  A pass requires at least one targeted mutation to make `conform` fail. Ignored
  metadata and fallback response scalars do not count as proof evidence; no
  targeted sites or budget-truncated targeted sets report inconclusive. A failed
  targeted mutation check refuses proof emission and removes any stale
  `<contract>.proven.json`.
- `--strict-freshness`: fail (not warn) when the cassette is stale or its recorded
  API version differs from `--reference-version`.
- `--max-cassette-age <dur>`: warn when the cassette's `recorded_at` is older than
  this (e.g. `720h`); `0` (default) disables the age check.
- `--reference-version <v>`: expected API version; a mismatch with the cassette's
  recorded `api_version` is flagged.

Stable JSON shape (emitted by default):

```json
{
  "contract": "contracts/widget.yaml",
  "overall_passed": false,
  "results": [
    {
      "name": "read_matches_create",
      "passed": false,
      "expected": "...",
      "actual": "...",
      "contract_path": "contracts/widget.yaml",
      "suggested_fix": "add refresh_after: true to lifecycle.create"
    }
  ],
  "repair_hints": ["add refresh_after: true to lifecycle.create"],
  "summary": { "passed": 5, "failed": 1, "total": 6 }
}
```

Loop: while `overall_passed` is false, apply the top `repair_hints` entry (see
`repair-hints.md`), re-run, repeat. A contract-validation failure surfaces through
the same stream with `name: "contract_validation"`, so there is one parse path for
both schema and replay failures. Exit code is non-zero when `overall_passed` is
false.

## completeness — does the contract model the full API surface?

```
agentprovider completeness <contract.yaml> [<cassette-or-fixtures-dir>] [--base-url <url>]
               [--openapi <spec>] [--operation <opId> | --path <path> --method <method>]
               [--metadata <json>] [--docs-evidence <json>] [--provider-schema <json>]
               [--probe-field <path>] [--allow-probes] [--allow-mutations]
               [--judge-input <path>] [--judge-command <cmd>] [--emit-judge-input]
               [--min-completeness <pct>] [--format json|text] [--json]
```

Diffs the contract's modeled fields (`attr.field` ∪ `identity.response_field` ∪
`ignore_server_fields`) against response fields the API actually exposes. The
summary gate (`advertised`, `missing`, `completeness_percent`, `passed`) stays
response-based; supplemental request/spec/docs/probe evidence feeds `fields[]`
and `suggestions[]`.

- **offline**: pass a go-vcr cassette / fixtures dir → unions recorded response
  fields for the summary gate and recorded request/response fields for
  classification evidence.
- **dynamic**: pass `--base-url` → issues a read-only GET against the contract's
  collection endpoint and unions what the live API returns right now.
- **spec/examples**: add `--openapi`, `--metadata`, `--docs-evidence`, or
  `--provider-schema` to merge deterministic or advisory evidence without
  treating docs/spec text as proof of writeability.

`--min-completeness <pct>` makes it a gate (exit 1 below threshold; default 0 =
report-only). Stable JSON (emitted by default): `{contract, kind, source,
advertised, modeled, completeness_percent, threshold, passed, missing[], extra[],
fields[], suggestions[], judge?}`.
`missing` =
advertised but unmodeled (model them, or add to `ignore_server_fields`); `extra` =
modeled but not seen in responses (a warning, never fails the gate — covers
write-only inputs and synthesized remaps). Limitation: response-union can't see
write-only inputs the server never echoes; model those from the API's docs.

`fields[]` carries deterministic classifications:

- `optional` / `optional_computed_defaulted` only becomes high-confidence when
  behavior shows omission succeeds, a supplied non-default value is accepted,
  the value reads back, and a second read is stable.
- `computed`, `response_only`, `volatile`, and `ignore_server_field` keep
  server-owned or unstable fields out of optional inputs.
- `needs_probe` names missing evidence. By default probes do not run; use
  `--probe-field <path> --allow-probes` for read-only evidence and add
  `--allow-mutations` only when live create/delete probe risk is acceptable.

`suggestions[]` is a reviewable patch plan, not an auto-repair. After applying a
suggestion, re-record if request shape changed, rerun `conform`, rerun
`completeness`, and only then proceed to proof. `--emit-judge-input`,
`--judge-input`, and `--judge-command` place model assistance under `judge`; it
is labeled advisory and cannot change classifications, thresholds, mutation
checks, proof sidecars, or served-provider readiness.

Use JSON and `jq` for checks rather than inline scripts:

```bash
agentprovider record contracts/widget.yaml --base-url "$BASE_URL" --out .agentprovider/cassettes/widget.cassette.yaml --suggest \
  | jq '.suggestions.field_suggestions'
agentprovider completeness contracts/widget.yaml .agentprovider/cassettes/widget.cassette.yaml \
  | jq '.summary, .suggestions'
```

## refresh — drift gate against the committed cassette

```
agentprovider refresh <contract.yaml> --base-url <url> [--cassette <path>] [--allow-mutations] [--format json|text] [--json]
```

Re-records the contract against the live API into a temp cassette and diffs it
against the committed one, reporting drift (changed status, changed response body,
added/removed requests). Exit is non-zero on drift, so it can gate a cadence
check. It reuses `record` for the live capture, so both sides are redacted the
same way before the diff. This is a freshness check on an already-proven contract,
not part of the bootstrap→conform authoring loop.

- `--base-url` (required): where to re-record against.
- `--cassette`: the committed cassette to diff against (defaults to the contract's
  standard cassette path).
- `--allow-mutations`: permit mutating calls during the re-record (same meaning as
  in `record`).

JSON shape (default). `drifted` is true and the exit code is non-zero when any
drift is found; `drift` entries are secret-sanitized:

```json
{
  "command": "refresh",
  "ok": true,
  "cassette": ".agentprovider/cassettes/widget.cassette.yaml",
  "drifted": true,
  "drift": ["GET /widgets/1: status 200 -> 404", "POST /widgets: response body changed"]
}
```
