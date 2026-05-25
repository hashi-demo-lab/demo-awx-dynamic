# agentprovider CLI authoring loop

All commands below use the `agentprovider` CLI; make sure it's available on your
PATH before you start. The core authoring subcommands are `bootstrap`, `record`,
and `conform`, with `completeness` (coverage gate) and `refresh` (drift gate)
alongside; serving an already-authored provider is separate (see `docs/RUNNING.md`).

Run `agentprovider help` for the command listing, and `agentprovider help <command>`
(or `agentprovider <command> -h`) for a command's flags.

## bootstrap — seed a draft contract

```
agentprovider bootstrap (--openapi <spec.yaml|json> [--operation <opId> | --path <p> --method <m>]
                   | --response <file.json|-> [--type <name>]
                   [--kind resource|datasource|ephemeral|action] [--action <verb>])
                   [--alias <param>=<attribute>]... [--ignore <name>]...
                   [--type <name>] [--out <path>]
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

## record — capture a replayable cassette

```
agentprovider record <contract.yaml> --base-url <url>
               [--out <cassette-path>] [--force] [--allow-mutations] [--suggest]
```

- `--base-url` (required): where to record against. For an unreviewed bootstrapped
  contract, use a **user-controlled staging URL**, not an embedded prod URL.
- `--allow-mutations`: permit mutating calls. Without it, resource
  create/update/delete and ephemeral renew/close are skipped (read-side only); an
  ephemeral contract's `lifecycle.open` still runs either way (it's how the
  ephemeral value is obtained).
- `--suggest`: print contract-refinement suggestions inferred from the responses
  (e.g. `ignore_server_fields` candidates from fields that change between reads).
- `--out`: defaults to `.agentprovider/cassettes/<type>.cassette.yaml`. `--force`
  overwrites.
- Secrets (auth headers, query secrets, OAuth2 tokens, `client_secret`) are
  redacted before the cassette is written. Review it before committing.
- The recorder refuses to persist a cassette whose recorded status is outside the
  contract's expectations (e.g. an error-shape contract must record its declared
  error status), so a bad live pass doesn't bless a wrong cassette.
- **Action-only contracts** (a `Resource` with `actions` and no `create`) record
  fine: `record` invokes the declared action verb against `--base-url` and captures
  the action request/response into the cassette. Pass `--allow-mutations` if the
  action mutates (e.g. a job launch). `conform` then replays it against
  `action_returns_expected`. No special flag is needed — `record` keys off the
  contract shape.

## conform — the machine verdict (the loop driver)

```
agentprovider conform <contract.yaml> <cassette.yaml>
               [--json] [--emit-proof] [--mutation-check]
               [--strict-freshness] [--max-cassette-age <dur>] [--reference-version <v>]
```

- `--json`: stable machine-readable output (use this in the loop).
- `--emit-proof`: on a passing run, write a `<contract>.proven.json` attestation
  binding the proof to the contract's content hash.
- `--mutation-check`: after a passing run, perturb the cassette and require at
  least one invariant to fail (proves the invariant set is non-vacuous).
- `--strict-freshness`: fail (not warn) when the cassette is stale or its recorded
  API version differs from `--reference-version`.
- `--max-cassette-age <dur>`: warn when the cassette's `recorded_at` is older than
  this (e.g. `720h`); `0` (default) disables the age check.
- `--reference-version <v>`: expected API version; a mismatch with the cassette's
  recorded `api_version` is flagged.

Stable JSON shape:

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
agentprovider completeness <contract.yaml> [<cassette-or-fixtures-dir>] [--base-url <url>] [--min-completeness <pct>] [--json]
```

Diffs the contract's modeled fields (`attr.field` ∪ `identity.response_field` ∪
`ignore_server_fields`) against the fields the API actually exposes. The reference
field set is generic and dynamic — there is no vendor schema parsing:

- **offline**: pass a go-vcr cassette / fixtures dir → unions the fields in the
  recorded responses.
- **dynamic**: pass `--base-url` → issues a read-only GET against the contract's
  collection endpoint and unions what the live API returns right now.

`--min-completeness <pct>` makes it a gate (exit 1 below threshold; default 0 =
report-only). Stable JSON: `{contract, kind, source, advertised, modeled,
completeness_percent, threshold, passed, missing[], extra[]}`. `missing` =
advertised but unmodeled (model them, or add to `ignore_server_fields`); `extra` =
modeled but not seen in responses (a warning, never fails the gate — covers
write-only inputs and synthesized remaps). Limitation: response-union can't see
write-only inputs the server never echoes; model those from the API's docs.

## refresh — drift gate against the committed cassette

```
agentprovider refresh <contract.yaml> --base-url <url> [--cassette <path>] [--allow-mutations]
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
