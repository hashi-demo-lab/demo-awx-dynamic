# Proposal: prefer `optional + default:` over naked `optional + computed` for server-defaulted scalars

- **Status:** Proposal — linchpin proven from source; ready to implement
- **Date:** 2026-05-29
- **Scope:** `terraform-provider-dynamic` / `agentprovider` CLI + the `agentprovider` skill (and its reference docs)
- **Engine source verified at:** `~/git/research-dynamic-provider/terraform-provider-dynamic` @ `3da3c91`
- **Framework verified at:** `terraform-plugin-framework@v1.19.0` (Go module cache)

## TL;DR

We have been authoring AWX contracts by **reflexively marking nearly every optional
attribute `optional: true, computed: true`** (≈38 of ~40 attributes on
`awx_job_template`). The justification — "AWX defaults almost every field, so we must
mark them computed to avoid *Provider produced inconsistent result after apply*" — is
**false as a blanket rule**: the engine already supports a static `default:` on optional
scalar attributes, and that shape is strictly better for any field whose server default
is a **known, stable scalar literal** (`false` / `0` / `""` / `"run"`).

The wrong assumption was treating *optional-and-unset* as a problem the provider must
absorb. An unset optional field is a legitimate, complete state. Defaulting to `computed`
because a field is optional converts "the user chose not to manage this" into "the server
owns this and Terraform won't police it" — which **silently disables drift detection** on
the majority of the schema. For a config-management tool, that is the core defect.

This doc proposes:

1. **CLI fix** (one function): make the `promote_to_optional_computed` correction emit
   `default: <server-literal>` when the server default is a stable scalar present in the
   cassette, falling back to naked `optional + computed` only when no scalar literal is
   available (objects/lists/multi-valued/genuinely-variable defaults).
2. **Skill fix**: replace the "promote to optional+computed" doctrine with a **four-way
   classification rubric** and reconcile the two reference docs that currently *forbid*
   `default:` for server values (they are stale).

The gate, schema builder, and validator **already support** the better shape today — only
the *suggestion emitter* and the *docs* steer authors the wrong way.

---

## 1. The four shapes and what each one means

| Shape | Use when | Drift detected when unset? | Reset-to-default by removing from config? |
|---|---|---|---|
| `computed: true` (no optional) | Server **generates** a value the client can't predict — `id`, timestamps, derived URLs | n/a (never user-set) | n/a |
| `optional: true, computed: true` (naked) | Server defaults the field but the default **varies** per instance/version (client can't know it) | **No** — absorbed silently | No (last value sticks) |
| `optional: true, default: <literal>` | Server defaults the field to a **known stable** scalar | **Yes** (proven — §3) | Yes |
| `optional: true` (plain) | User-or-nothing; server returns null/empty when omitted | Yes | n/a |

The current contracts collapse rows 2 and 3 into row 2. The fix is to push the large
"known stable default" bucket into row 3.

### Worked classification — `awx_job_template`

- **`computed` only:** `id`. ✅ already correct.
- **`optional + default:`** (the big bucket — known stable literals):
  - bool → `default: false`: every `ask_*_on_launch`, `become_enabled`, `diff_mode`,
    `allow_simultaneous`, `force_handlers`, `use_fact_cache`, `survey_enabled`.
  - number → `default: 0`: `verbosity`; `default: 1`: `job_slice_count`.
  - string → `default: ""`: `description`, `extra_vars`, `job_tags`, `skip_tags`,
    `start_at_task`, `host_config_key`, `limit`, `scm_branch`; `default: "run"`: `job_type`.
- **`optional + computed` (naked), pending a per-instance/version variance check:**
  `forks`, `timeout` (may inherit from AWX global settings — only here is "can't predict"
  arguably true).
- **plain `optional`:** `inventory`, `project` (FKs; server leaves null when omitted).
  ✅ already correct.
- **`ignore_server_fields` (unchanged):** `url`, `related`, `summary_fields`, `created`,
  `modified`, `status`, `last_job_run`, `next_job_run`, `type`, `organization`
  (rolled-up FK). Genuine server-owned outputs. ✅ already correct.

Net: of ~38 currently naked `optional+computed`, **~30 should become `optional+default`**,
~2 may legitimately stay naked (pending variance check), and `id`/FKs are already right.

---

## 2. Why the "we had no choice but computed" excuse is false — engine evidence

All references are to `~/git/research-dynamic-provider/terraform-provider-dynamic` @ `3da3c91`.

### 2a. The validator already accepts `optional + default` without `computed`, including numbers

`internal/contract/validate.go:549-572`: `default` requires **`Optional`** (not `Computed`),
forbids `sensitive`, and accepts `bool` / `string` / `number` (numbers via
`numericDefaultError`; cf. commit `0bebb75 prove numeric static defaults`). Only sensitive
and non-scalar (object/list) defaults are rejected.

### 2b. The schema builder turns `default:` into `Default + Computed` with **no** `UseStateForUnknown`

`internal/contract/schema.go:37-88` (string; number/bool identical):

```go
if a.Default != nil {
    at.Default = stringdefault.StaticString(fmt.Sprint(a.Default))
    at.Computed = true                                   // framework rule: Default requires Computed
}
if isIdentity && at.Computed {                           // <-- ONLY the id gets UseStateForUnknown
    at.PlanModifiers = []planmodifier.String{stringplanmodifier.UseStateForUnknown()}
}
```

`UseStateForUnknown` is gated on `isIdentity`. Non-identity attributes — every field we
care about — never get a state-preserving plan modifier. (Whole-repo grep confirms the
only non-test `UseStateForUnknown` is here, identity-gated, plus the datasource/ephemeral
builders which have no Default concept at all.)

### 2c. The `optional_default_consistency` gate already passes `optional + default`

`internal/conformance/invariants.go:149-204`. Skips anything not `(optional && !computed)`
(line 158), then for an optional-not-computed attr **with** a default (lines 166-188):
passes iff the field is in `create.body`, or the cassette shows omitted-create evidence
whose observed value **matches** the declared default (`observedDefaultMatches`, number-aware,
215-232). For optional-not-computed **without** a default (189-200): fails iff the cassette
shows the server returns a non-null default on omit. So the pass condition is
**"computed, OR a declared default matching the server's omitted value"** — not bare
`computed == true`. The gate comment says so explicitly (161-165).

### 2d. The suggestion emitter is the only thing steering us wrong

Classifier flags already-modeled optional-not-computed fields the cassette shows defaulted
(`internal/contract/field_classification.go:97-101`,
`NextAction = "promote_to_optional_computed"`). The emitter then **hard-codes
optional+computed and never emits `default:`** (`cli/agentprovider/field_suggestions.go:146-170`):

```go
attr := map[string]any{"type": suggestedAttrType(field.Evidence.Type), "optional": true}
if computedDefault { attr["computed"] = true }     // <-- always computed, never default
```

The server's literal is already in hand: `FieldEvidence.ObservedValues` (populated from the
cassette by `EvidenceFromInteractions`), and the conform/completeness path merges
interactions before classifying. There is even a working template for emitting a typed
literal: `suggestedDefaultValue` (`field_suggestions.go:172-198`), today used only for the
*unmodeled* `add_optional_default_attribute` path.

---

## 3. Linchpin — PROVEN: framework re-asserts defaults on update (drift detection restored)

The §1/§2b claim "`default:` restores drift detection on **update**" rests on
terraform-plugin-framework applying a `Default` whenever the config value is null on
**both create and update**. This is now **confirmed from v1.19.0 source** (and
independently cross-checked by GPT-5.5 at xhigh reasoning, read-only):

- `internal/fwserver/server_planresourcechange.go:161,169` — `TransformDefaults(ctx,
  req.Config.Raw)` is called inside `if !resp.PlannedState.Raw.IsNull()`. The **only**
  guard is a non-null *planned* state (false only on destroy). There is **no**
  `PriorState.IsNull()` create-only condition. → runs on create **and** update.
- `internal/fwschemadata/data_default.go:21-23, 82-100` — `TransformDefaults` applies the
  default wherever the **config value is null** ("Do not transform if rawConfig value is
  not null"), returning the default as the planned value and **overwriting** whatever was
  in the planned state. It never consults prior state. On update, the planned value for an
  unconfigured field is the refreshed (drifted) prior value → the default overwrites it →
  **corrective diff**.
- `internal/fwserver/server_planresourcechange.go:398-402` — the "mark Computed-only as
  unknown" block runs "only on create or update operations, not destroy, and only for
  attributes that do not already have a default value applied **or a known planned
  value**." So naked `optional+computed` (config null, known prior value) is left at the
  prior (drifted) value → **no diff → drift absorbed silently.** This is exactly the
  contrast.

**Conclusion (verified, not assumed):** for scalar string/number/bool attributes,
`optional + default: <literal>` re-asserts the default on update and produces a corrective
diff when the server drifted; naked `optional + computed` does not. The "restores drift
detection" claim holds.

*Caveat (scope):* proven for scalar string/number/bool. Collections/objects flow through
the same transform but have different null/element semantics — out of scope here (the AWX
fields in question are all scalars). A live drift test (§6 step 1) remains a cheap
belt-and-suspenders confirmation but is no longer gating.

---

## 4. Proposed CLI fix

**One function, in `cli/agentprovider/field_suggestions.go`.**

1. **Emit `default:` from the promote path when a stable scalar literal exists.**
   In `addAttributeSuggestionWithAction` (line 146), for `action ==
   "promote_schema_attribute"`, derive a literal from the cassette evidence and, if
   present, set `attr["default"] = <literal>` and **omit** `attr["computed"]`. Fall back to
   the current naked `optional + computed` only when no scalar literal is available.

2. **Source the literal from `ObservedValues`, not `DefaultSummary`.**
   `suggestedDefaultValue` (line 172) bails because it gates on `field.Evidence.HasDefault`
   (false for a not-yet-declared field). Add a sibling (e.g. `observedScalarDefault`) that
   reads `field.Evidence.ObservedValues` when:
   - `field.Evidence.Defaulted` is true (server returns a meaningful default on omit), **and**
   - there is exactly **one** observed value (stable across the cassette), **and**
   - `suggestedAttrType(field.Evidence.Type)` ∈ {string, number, bool}.

   Parse to a typed int/float/bool/string exactly like `suggestedDefaultValue`. Any failure
   (object/list/map/set, multi-valued, non-scalar) → `(nil, false)` → caller falls back to
   naked `optional + computed`.

3. **Update suggestion text** (`formatSuggestionText`, line 250) for
   `promote_schema_attribute`: `"promote %s to optional + default <literal> (or
   optional+computed if the default varies per instance)"`.

**No change required to** the gate (`invariants.go` already passes `optional+default`), the
schema builder (`schema.go` already wires it correctly with no UseStateForUnknown), or the
validator (`validate.go` already accepts it). The fix is purely in what the tool *suggests*.

Because we emit `default = ObservedValues[0]` (the server's omitted-create value), the
resulting suggestion **passes `optional_default_consistency` by construction** (the declared
default equals the observed default).

### Single-cassette limitation (state it honestly in output)

The CLI sees one recording, so it can observe the single default value but **cannot** know
whether that default *varies per instance/version*. The suggestion should carry a one-line
note: *"If this default varies by AWX instance or version, use `optional + computed`
instead of `default:`."* The human makes the variance call; the tool defaults to the
higher-information shape because it is correct for the common case.

---

## 5. Proposed skill fix

**Mirror rule first:** `.agents/skills/agentprovider/SKILL.md` and
`.claude/skills/agentprovider/SKILL.md` must stay byte-identical, but they are **currently
out of sync** (`.claude` is an older, ~46-line-shorter revision). **Resync `.claude` to
`.agents`** (and the `references/` dir) as part of this change, then apply edits to the
canonical `.agents` copy. (Line numbers below are for `.agents`.)

### SKILL.md edit sites

- **Lines 478-486 (primary home).** Already diagnoses the drift-loss problem but still
  prescribes `optional+computed`. Rewrite so `default: <literal>` is the **primary** remedy
  for a server default to a known stable scalar (it silences `optional_default_consistency`
  *and* keeps drift detection), naked `optional+computed` is reserved for per-instance/version
  varying defaults, and `computed`-only is for server-*generated* values. Anchor the
  **four-way rubric** (§1 table) here.
- **Lines 254-259.** `promote_to_optional_computed` description: note the correction now
  emits `default: <literal>` for stable scalars, `optional+computed` otherwise.
- **Lines 285-291.** `ignore_server_fields` "one question" rubric: split the
  "a default (`""`, `0`, `false`)" case — known stable literal → `default:`; canonicalized
  / varying → `+computed`.
- **Lines 304-306.** Behavior-toggle paragraph: `(+default: <literal> when the server
  defaults it to a stable scalar; +computed only when the default varies)`.
- **Lines 462-466.** Example/replay-trap mention: make consistent — a `default:`-bearing
  field is also sent in the body and has the same `conformance.example`/`update_to`
  constraint. Minor.

### Reference-doc reconciliation (these currently *contradict* the engine)

- **`references/contract-format.md:137-148` — STALE, must rewrite.** Currently says *"Do not
  use `default` to absorb a value the server fills in … declare `optional: true, computed:
  true`"* and *"a number … with `default` is rejected at load."* Both false against
  `3da3c91`: the gate passes `optional+default` (`invariants.go:166-188`) and the validator
  accepts numeric defaults (`validate.go:565-568`). Rewrite to present `default:` as the
  preferred remedy for stable scalar server-defaults and drop the numeric-rejection claim.
- **`references/repair-hints.md:20,64-71` — add the default branch.** The
  `optional_default_consistency` fix currently lists only "declare `optional: true,
  computed: true`." Add: *"or declare `optional: true, default: <server-literal>` for a
  stable scalar default — this satisfies the gate (the engine forces computed internally)
  and preserves drift detection."*

### Harness — no change needed

`agentprovider-workspace/harness/quality_analyze.py` `classify()` keys only on
`optional`/`computed`/`required` and credits an `optional + default` field as settable
(classifies as `"optional"`). It never reads `default`, and `settable_dumped_to_ignore` is
independent of it. The better shape is **not** penalized. Optional cosmetic nicety: add a
`default` column to the printed table.

---

## 6. Validation plan

1. **Live drift test (optional, mechanism already proven in §3).** Convert
   `awx_job_template.verbosity` to `optional + default: 0`, `apply`, change `verbosity` to 4
   via the AWX API, `plan`. Expect a corrective `4 → 0` diff. Belt-and-suspenders.
2. **Gate still green.** Re-run `agentprovider conform` + `completeness` on the converted
   contract; confirm `optional_default_consistency` passes via the `attr.Default != nil`
   branch and `overall_passed: true` holds.
3. **CLI suggestion check.** With the fix, run conform/completeness on a contract with an
   un-promoted server-defaulted scalar; confirm the suggestion now carries
   `default: <literal>` (and falls back to `optional+computed` for a non-scalar/varying field).
4. **Quality score unchanged-or-better.** Re-run `quality_analyze.py`; settable-coverage
   must not regress.

## 7. Rollout / backward compatibility

- The CLI change only alters *suggestions*; existing contracts with naked
  `optional+computed` keep working (the gate still skips them). No breaking change.
- Converting contracts is opt-in and per-field; mixed shapes are valid.
- Sensitive and non-scalar fields are untouched (validator forbids defaults there).
- Numeric defaults rely on `0bebb75`; confirm the shipped CLI build in this repo includes it
  before converting numeric fields.

## 8. Open questions

- **`forks` / `timeout` variance** — do these inherit AWX global settings such that their
  default varies per instance? If yes, they legitimately stay naked `optional+computed`; if
  no, demote to `default:`.
- **Auto-detect "varies"?** The CLI can't from one cassette; leaving the call to the human
  (with a suggestion-text hint) is the proposed behavior.

---

## Appendix — verified source references

**Engine** (`~/git/research-dynamic-provider/terraform-provider-dynamic` @ `3da3c91`):

| Claim | File:line |
|---|---|
| `UseStateForUnknown` only on identity; `default:` ⇒ `Default`+`Computed`, no plan modifier | `internal/contract/schema.go:37-88` |
| `default` requires optional (not computed); numbers accepted; sensitive/non-scalar rejected | `internal/contract/validate.go:549-572` |
| `optional_default_consistency` passes `optional+default` matching omitted-create evidence | `internal/conformance/invariants.go:149-204` |
| Promote emitter hard-codes `optional+computed`, never `default:` | `cli/agentprovider/field_suggestions.go:146-170` |
| Existing typed-literal emit template (`suggestedDefaultValue`) | `cli/agentprovider/field_suggestions.go:172-198` |
| Promote classification requires cassette-`Defaulted` evidence | `internal/contract/field_classification.go:97-101` |
| Server literal available in evidence (`ObservedValues`) | `internal/contract/field_evidence.go` |

**Framework** (`terraform-plugin-framework@v1.19.0`, drift-on-update proof — §3):

| Claim | File:line |
|---|---|
| `TransformDefaults` called on create+update (guard = non-null planned state) | `internal/fwserver/server_planresourcechange.go:161,169` |
| Default applied wherever config is null; overwrites planned (prior) value | `internal/fwschemadata/data_default.go:21-23,82-100` |
| Naked computed left at known prior value (drift absorbed) | `internal/fwserver/server_planresourcechange.go:398-402` |

Linchpin (drift-on-update) independently confirmed by GPT-5.5 (xhigh, read-only) on 2026-05-29.
