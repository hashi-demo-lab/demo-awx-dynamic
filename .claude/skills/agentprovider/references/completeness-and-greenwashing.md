# Completeness, classification, and green-washing

Deep reference for step 4 (`agentprovider completeness`). SKILL.md carries the
short version; read this when classifying fields, hitting a green-washing refusal,
or completing a verbose resource.

## What `completeness` reports

It reports `completeness_percent`, the `missing` fields (the API returns them but no
attribute models them), and `extra` (modeled but not seen — usually fine). It also
emits `fields[]` classifications and `suggestions[]` review artifacts. Use those
before source-diving or making name-based schema edits:

- `optional` / `optional_computed_defaulted` with high confidence can become a
  schema attribute suggestion. A field **already modeled** `optional` (not
  `computed`) that the cassette shows the server defaults is surfaced as a
  `promote_to_optional_computed` correction. When the recorded omit-create response
  is a **stable scalar literal**, the suggestion carries `optional: true` +
  `default: <literal>` (*"set default:<v> on <path> to keep it plan-known and
  preserve drift detection"*) — the CLI pins the literal from that create-filtered
  value. When the default isn't a pinnable scalar (object/list, canonicalized,
  variable), it falls back to `promote_schema_attribute` carrying
  `optional: true, computed: true`. Apply whichever it emits, or the
  `optional_default_consistency` conform gate fails closed. Prefer `default:` over
  `computed:` whenever a literal is offered (see the four-way rubric in
  `references/gotchas.md`).
- `volatile` / `ignore_server_field` candidates usually belong in `ignore_server_fields`.
- `needs_probe` means the current evidence is not enough to promote the field. Add
  `--probe-field <path> --allow-probes` for read-only evidence, and `--allow-mutations`
  only when you explicitly accept create/delete probe risk.
- `--emit-judge-input`, `--judge-input`, `--judge-command` are advisory only; model
  output must never determine proof readiness.

The reference field set is generic and dynamic: recorded request/response bodies,
cassette responses, OpenAPI request/response schemas, optional metadata/docs
evidence, or a live read (`--base-url`). `--min-completeness` makes it a gate
(non-zero exit below the threshold). Weigh `missing` by **practitioner relevance,
not count** — some entries are artifacts of a response shape you don't model (an
error/`detail` envelope, a delete body). Response-union can't see *write-only* inputs
the server never echoes — model those from the API's docs/specs.

## The one test that classifies every field

**`ignore_server_fields` is for server-*owned* output only — not a dumping ground to
hit a number.** Before you ignore a field, ask: **does the API accept this field as
a create/update input?** (Check the request schema — OpenAPI request body, an
`OPTIONS`/`POST` field listing, or the documented create-body.) If yes, it is a
**practitioner knob** → `schema.attributes` as `optional: true`, not ignored.

When the server *supplies a value you didn't send*, the field is server-defaulted and
must absorb that value — but **prefer `optional + default: <literal>` over
`optional + computed`** whenever the omit-default is a **stable scalar** (`""`, `0`,
`false`, `"run"`, …): a static default keeps the unset value plan-known **and**
preserves drift detection, where `computed` is drift-blind on the unset field.
Reserve `optional + computed` for defaults that can't be pinned (canonicalized input,
object/list/variable). Do **not** mark a field computed merely because the server
echoes it back: an optional input the server leaves **null/absent** when omitted
stays `optional`-only (plain).

**Reserve `ignore_server_fields`** for fields the practitioner can never set —
timestamps, `related`/`_links`, `summary_fields`, computed status, counters, error
envelopes (`detail`).

### Efficiency — seed the obvious envelope in one pass

These server-owned keys recur on almost every verbose REST object, so declare the
standard set up front rather than rediscovering them one `completeness` re-run at a
time (each rediscovery costs a record/completeness cycle): `detail` (error envelope),
`related`, `_links`, `summary_fields`, `url`/`named_url`, `type`, `created`/`modified`
(and `*_by`), and any `*_role`/`object_roles`. Add object-specific computed
counters/status (`total_*`, `has_*`, `last_job_*`, `*_run`) once `completeness` names
them. Pre-listing the common envelope typically takes a fresh resource from ~90% to
100% in the first pass instead of two or three.

### FKs and behavior toggles are settable

**A foreign-key / reference id is a settable input, not server-owned** —
`*_credential`, `execution_environment`, `default_environment`, `*_environment`, a
parent/`organization`/`project` id, and similar reference fields are accepted on
create/update, so they belong in `schema.attributes` as `optional` FKs. The tell is
that the field *names a related object*: if the practitioner could point it at a
different object, it is a knob.

**Behavior toggles are settable knobs too** — boolean/enum flags such as `enable_*`,
`allow_*`, `*_enabled`, and the whole `ask_*` / `*_on_launch` family that a verbose
API accepts in its create/update body. A verbose object can carry a dozen-plus of
them, and they are the single biggest green-washing trap (easy to wave off as
"launch-time behavior" and dump). If the request schema accepts the flag, model it
`optional` (`+computed` when the server defaults it).

The completeness gate may not catch this on an API that exposes no request schema
(response-union can't tell a settable input from a server-supplied one), so classify
by the one test — **"does the create/update body accept this field?"** — not by where
the value comes from or whether it "feels" like core config. Ignoring a *settable*
field to clear the gate is **green-washing**: completeness reads 100% but you ship a
resource that can't configure most of the API. Self-check: count the
`optional`/`optional+computed` attributes against the API's settable-input list — if
you model a handful while ignoring dozens of settable fields, you green-washed.

## Let the tool measure green-washing

`completeness` reports a **`settable_coverage`** ratio and an **`ignored_settable`**
list on every run — derived from the **recorded create/update request bodies in the
cassette**, free with no extra flag. A `settable_coverage` below `1` (or non-empty
`ignored_settable`) means you parked a field you are *actually sending* into
`ignore_server_fields` — model it `optional` instead.

**Blind spot:** cassette-derived settable only sees fields the contract *already
sends*. An input the API accepts that you never modeled and never sent leaves no
request-body evidence, so it is invisible — `settable_coverage` reads a false `1.0`
even when you dumped a dozen real knobs. **The fix that makes quality reproducible is
to feed a request schema**, which lists every accepted input the cassette can't see:

```bash
# OpenAPI: you already have the spec
agentprovider completeness contracts/widget.yaml <cassette> --openapi spec.yaml --operation createWidget
# DRF / Django-REST API (no OpenAPI): use introspect for discovery; for a reusable
# proof gate save the reviewed full OPTIONS envelope (or wrap a reviewed POST map as
# {"actions":{"POST":...}}).
agentprovider introspect /api/v2/widgets/ --base-url "$BASE_URL" --auth-env AWX_TOKEN --format json
agentprovider completeness contracts/widget.yaml <cassette> --metadata widget.options.json --min-settable-coverage 90
```

With a schema fed, `ignored_settable` names every accepted input you dumped, and —
crucially — **`conform --mutation-check --emit-proof` takes the same
`--metadata`/`--openapi` and refuses to write the proof** with `green-washing
refusal: ignored N settable inputs …`. So **whenever the API serves a schema
(OpenAPI, or a DRF `OPTIONS` envelope with `actions.POST`), pass it to both
`completeness` and `emit-proof`** — a green-washed contract then *cannot* be proven.
(Credential and read-only fields are excluded automatically.) Only when the API
exposes no schema at all do you fall back to the cassette-only signal plus the
one-test judgement.

## Kind-specific

- This guard is about **settable inputs**, which only exist on a contract with a
  create/update body (resources). A **read-only DataSource or Ephemeral has no
  settable inputs** — every field is a computed output — so routing the non-projected
  server envelope into `ignore_server_fields` is *legitimate*, not green-washing. The
  quality bar is the inverse: **model the practitioner-useful outputs as `computed`**
  (don't leave a data source projecting three fields), then ignore the pure envelope.
- Completeness is a **resource / data-source** gate. An **action-only or ephemeral**
  contract models only the verb's inputs + a few outputs, so its completeness against
  a full read payload is **low by design — not a defect**. Judge an action by
  `action_returns_expected`, not a percentage; don't point `--min-completeness` at
  one. That is also why `--emit-proof` (which requires 100%) does not apply to
  action/ephemeral kinds — prove them at `conform`, not with a sidecar.

`record --suggest` also flags `unmodeled_fields` and field-level suggestions so you
catch gaps at record time. It still does not edit the contract for you.
