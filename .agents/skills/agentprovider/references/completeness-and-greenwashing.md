# Completeness, classification, and green-washing

Deep reference for field classification. SKILL.md carries the one-test short
version; read this when hitting a green-washing refusal or completing a verbose
resource.

## What `completeness` reports

`completeness_percent`, `missing` (API returns them, no attribute models them),
`extra` (modeled but unseen — usually fine), plus `fields[]` classifications and
`suggestions[]`. Use the suggestions before source-diving:

- `promote_to_optional_computed` / `promote_schema_attribute` — a field the cassette
  shows the server defaults. When the omit-create value is a **stable scalar literal**
  the suggestion carries `optional: true, default: <literal>`; otherwise it falls back
  to `optional: true, computed: true`. Apply whichever it emits or the
  `optional_default_consistency` gate fails closed. Prefer `default:` over `computed:`
  whenever a literal is offered (rubric in `references/gotchas.md`).
- `ignore_server_field` candidates → `ignore_server_fields`.
- `needs_probe` — evidence insufficient; add `--probe-field <path> --allow-probes`
  (read-only), `--allow-mutations` only if you accept create/delete probe risk.
- `--emit-judge-input`/`--judge-*` are advisory only; model output never determines proof.

Weigh `missing` by **practitioner relevance, not count** — some entries are artifacts
of a shape you don't model (an error/`detail` envelope, a delete body). Response-union
can't see **write-only** inputs the server never echoes — model those from docs/specs.

## Standard server envelope — seed it in one pass

These server-owned keys recur on almost every verbose REST object; declare the set up
front rather than rediscovering them one re-run at a time (each costs a
record/completeness cycle): `detail`, `related`, `_links`, `summary_fields`,
`url`/`named_url`, `type`, `created`/`modified` (and `*_by`), `*_role`/`object_roles`.
Add object-specific computed counters/status (`total_*`, `has_*`, `last_job_*`,
`*_run`) once `completeness` names them. This typically takes a fresh resource from
~90% to 100% in the first pass.

## FKs and behavior toggles ARE settable

A **foreign-key / reference id** (`*_credential`, `execution_environment`,
`*_environment`, a parent/`organization`/`project` id) is accepted on create/update →
`schema.attributes` as an `optional` FK, not ignored. The tell: it *names a related
object* the practitioner could repoint.

**Behavior toggles** (`enable_*`, `allow_*`, `*_enabled`, the whole `ask_*` /
`*_on_launch` family) are settable knobs too, and the single biggest green-washing
trap (easy to wave off as "launch-time behavior" and dump). If the request schema
accepts the flag, model it `optional` (`+computed` when the server defaults it).

Classify by the one test — **"does the create/update body accept this field?"** — not
by where the value comes from. Ignoring a *settable* field to clear the gate is
**green-washing**: 100% completeness but a resource that can't configure the API.
Self-check: model a handful while ignoring dozens of settable fields = green-washed.

## Let the tool measure green-washing

`completeness` reports **`settable_coverage`** and **`ignored_settable`** on every run,
derived from the **recorded request bodies in the cassette** (free, no flag).
Coverage below `1` (or non-empty `ignored_settable`) means you parked a field you are
*actually sending* into `ignore_server_fields` — model it `optional`.

**Blind spot:** cassette-derived settable only sees fields the contract *already
sends*. An accepted input you never modeled leaves no request-body evidence, so
`settable_coverage` reads a false `1.0`. The fix that makes quality reproducible is to
**feed a request schema**:

```bash
# OpenAPI
agentprovider completeness contracts/widget.yaml <cassette> --openapi spec.yaml --operation createWidget
# DRF (no OpenAPI): save the reviewed full OPTIONS envelope (or wrap a POST map as {"actions":{"POST":...}})
agentprovider completeness contracts/widget.yaml <cassette> --metadata widget.options.json --min-settable-coverage 90
```

With a schema fed, `ignored_settable` names every dumped input, and **`prove` /
`conform --mutation-check --emit-proof` take the same `--metadata`/`--openapi` and
refuse the proof** with `green-washing refusal: ignored N settable inputs …` — so a
green-washed contract *cannot* be proven. (Credentials and read-only fields are
excluded.) Only when the API serves no schema do you fall back to the cassette-only
signal plus the one-test judgement.

## Kind-specific

- A **read-only DataSource / Ephemeral has no settable inputs** — routing the
  non-projected server envelope into `ignore_server_fields` is legitimate. The bar is
  the inverse: **model the practitioner-useful outputs as `computed`** (don't ship a
  data source projecting three fields), then ignore the pure envelope.
- Completeness is a **resource / data-source** gate. An **action/ephemeral** models
  only the verb's inputs + a few outputs, so low completeness is **by design** — judge
  by `action_returns_expected`, not a percent, and don't point `--min-completeness` /
  `--emit-proof` at it (prove those at `conform`, no sidecar).

`record --suggest` also flags `unmodeled_fields` at record time (never auto-edits).
