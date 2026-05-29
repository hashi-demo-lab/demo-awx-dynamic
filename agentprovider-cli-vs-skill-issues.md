# agentprovider — CLI vs Skill issues log

Running log of friction observed while optimizing the **agentprovider skill**
against the live AWX full-stack eval (`evals/awx-live.json`). Every entry is
classified by where the fix belongs, because the two have different owners:

- **`skill`** — the `SKILL.md` / `references/*` guidance could have prevented the
  friction. Fix it here, keeping the guidance **generic** (AWX is only the test
  instance — no AWX-specific text in the skill).
- **`cli_engine`** — the `agentprovider` CLI or the runtime engine behaved
  surprisingly, emitted a misleading message, or could do more for the author.
  These are upstream improvements to `terraform-provider-dynamic`, NOT authoring
  failures. The skill may still add a one-line workaround, but the *root* fix is
  in the tool.
- **`environment`** — an artifact of the shared live-AWX harness (leftover
  objects, state reuse). Not actionable in skill or CLI.

Severity: `high` (caused a failure / repair loop) · `med` (cost time or a
dead-end) · `low` (cosmetic / noise) · `info` (observation).

Entry format: `[round] severity | class | symptom → fix / where it belongs`.

Prior pass history (5-round + 3-round, v0→v3) lives in
[`agentprovider_log.md`](agentprovider_log.md). This file is the current pass and
sharpens the **CLI-vs-skill split** the maintainer asked for.

---

## Carried forward from the prior pass (open CLI-side candidates)

These were observed earlier and resolved in the skill with a workaround, but the
*durable* fix is a CLI/engine improvement. Re-confirm or close each as the rounds
re-exercise them.

- **CF-1 low | cli_engine** — `record --suggest` is resource-tuned: on an
  action-only contract it proposes an `identity.response_field` the author must
  ignore (an action has no identity). The CLI could detect an action-only contract
  and suppress the identity suggestion. *Skill workaround in place:* "ignore that
  suggestion on action-only contracts."
- **CF-2 low | cli_engine** — cassette redactor matches credential values by
  substring, so a short/common value (e.g. username `admin`) shows as a "redaction
  hit" against unrelated field-name text. Conservative over-match, not a leak; the
  CLI could scope matching to credential-bearing fields. *Skill workaround:* tells
  the author how to read such a match.
- **CF-3 info | cli_engine** — `bootstrap` does not emit `allow_insecure` /
  `allow_private_host` for a plaintext/private target, so the SSRF/transport guard
  only trips at `record`/`plan`. The CLI could infer them from an `http://` or
  RFC-1918 base_url at bootstrap. *Skill workaround:* "Get these right up front."
- **CF-4 low | cli_engine→skill** — a by-id data source / by-id action needs its
  target object to EXIST at record time (record hits the live API). A clearer
  `preflight`/`record` message ("path interpolates ${id}; ensure a target exists")
  would localize it. *Skill workaround:* record-step "create a fixture first" note.
- **CF-5 info | skill (declined)** — a numeric completeness heuristic ("15–25% is
  normal for verbose objects"). Declined as overfitting; the generic "weigh by
  relevance, not count" + "actions are low by design" guidance stands.

---

## Round 1 — skill v0 (baseline)

**Result: PROVEN, 8/8 objective assertions, 0 conform repairs, 0 Go-source reads.**
7/7 contracts conform; completeness 100% on all 4 resources + the data source; live
`terraform apply` created the graph; `awx_job_launch` launched job 163 and
`aap_workflow_job_launch` launched workflow job 164; second plan a no-op; no
credential in any artifact. 8.7 min, 134K tokens, 70 tool calls. The skill is at
its prior noise floor — these are *refinements*, not failures.

- **R1-1 high | cli_engine** — *`record` emits a false-positive "will fail conform
  on re-record" warning on every CRUD resource whose update changes a field.* The
  warning ("conformance.example pins description=X but the live run observed X
  updated … this contract will fail conform on re-record. Move description out of
  conformance.example into conformance.expect.description: {not_null: true}") fired
  on org/inventory/job_template/host; **conform passed 10/10 anyway.** Root cause: the
  recorder compares `conformance.example` against the **last** observed value
  (post-update), but conform checks `example` against **create-time** state and
  `update_to` against the updated state — so `example != update_to` is correct by
  design, and a re-record reproduces a matching cassette. The warning is wrong, and
  its *suggested fix actively harms the contract*: moving the field to
  `expect.<f>: {not_null: true}` drops the create-time value check in
  `create_echoes_inputs`. **CLI fix:** compare the example against the create-phase
  observation, not the final one (or suppress when the field appears in `update_to`).
  *Skill mitigation added (v1):* a precise note that this warning is a false positive
  for any field you intentionally change in `update_to`, and not to follow its
  weaken-the-contract suggestion.
- **R1-2 high | skill** — *`--emit-proof` requires 100% completeness, and the skill
  never says so.* Verified directly: emit-proof on the action contract printed
  `emit proof: completeness 5% is below proof threshold 100%` and wrote no sidecar
  (cli-loop.md:208 documents the 100% gate). On a verbose API you reach 100% by
  routing the **server-owned envelope** (relations, summaries, links, timestamps,
  capability flags) into `ignore_server_fields` — a non-request change, so **no
  re-record**. The agent inferred this; the skill should state the threshold and the
  route. *Skill fix added (v1)* in the proof step + a completeness pointer.
- **R1-3 high | skill (+cli_engine angle)** — *emit-proof's 100% gate makes it a
  resource/data-source-only step; action-only & ephemeral contracts cannot be
  emit-proofed.* Their completeness is low-by-design (5% / 8%), below the 100% proof
  threshold, so emit-proof is refused and there is no `.proven.json` for them — that
  is correct, but the skill's proof step implies you emit-proof *every* contract, so
  a careful author hits a hard refusal and may wrongly try to inflate an action's
  completeness. *Skill fix added (v1):* prove actions/ephemerals at
  `conform`(+`--mutation-check`); don't expect a proof sidecar. **CLI candidate:**
  emit-proof could support a kind-appropriate proof for actions/ephemerals (attest on
  their own invariants) instead of a flat 100% gate that those kinds can never meet.
- **R1-4 info | environment** — first `terraform plan` failed with `AWX_PASSWORD …
  unset or empty` until `.env` was sourced from the repo root. Pure harness artifact
  of this repo's root-relative password file (already in project memory); not skill-
  or CLI-actionable.

**Carried-forward status:** CF-1 (suggest identity on actions) and CF-3 (bootstrap
SSRF flags) did not recur to cost anything — both action contracts and the
`http://localhost` target were handled up front by existing skill guidance (named in
`skill_callouts`). CF-2 (redactor over-match) not exercised (Basic auth, creds in
header). CF-4 (by-id fixture at record time) handled cleanly by the data source.

## Round 2 — skill v1

**Result: PROVEN, 8/8 objective assertions, 0 repairs, 0 Go reads.** Tokens
**134K → 113K** (the emit-proof/completeness guidance removed dead-ends). Job 169 +
workflow job 170 launched; idempotent replan; no leak. The three v1 edits were
confirmed working **by name** in the run's `skill_callouts`:

- R1-1 fixed → *"ignored the example!=update_to warning per SKILL guidance."*
- R1-2 fixed → *"emit-proof's 100% completeness gate is reached by routing the
  server-owned envelope to ignore_server_fields (a non-request change, no re-record)
  — got proven.json sidecars for all 4 resources and the data source."*
- R1-3 fixed → *"actions are proven at conform with --mutation-check (no emit-proof
  sidecar) … kept me from trying to inflate action completeness."*

New friction — one item, **investigated and dismissed**:

- **R2-1 ~~cli_engine~~ → non-issue (verified)** — the agent reported that
  `conform --mutation-check` / `record --suggest` "prepend a non-JSON human line
  before the JSON, so naive `json.load(stdout)` fails." **Ground-truth check: stdout
  is pure JSON.** Running `conform … --mutation-check 2>/dev/null | python -c
  'json.load(sys.stdin)'` parses cleanly; the `mutation check: targeted invariants
  bite …` status line is on **stderr**, and `record`'s warnings are *also* embedded
  in the JSON `warnings[]` array. The apparent "mixing" came only from the run's
  visible-terminal brief capturing merged streams (`2>&1`). Streams are correctly
  separated — **no CLI change, no skill change.** Logged so it isn't re-filed as a
  bug. (Operational note for any JSON-parsing harness: read stdout alone, not
  `2>&1`.)
- **R2-2 environment** — launched job 169 showed AWX status `failed`. The launch
  POST returned 201 + job id + pending (what the action contract asserts); the
  `failed` is the *playbook runtime* result for a brand-new job_template with no
  real project/inventory content — downstream of, and outside, what the launch
  action proves. Not skill/CLI actionable.

**Convergence note:** v1 produced no new actionable edit — round 2 only confirmed
the v1 fixes and dismissed one misattribution. The skill has re-reached the noise
floor at v1. Round 3 is a stability/variance check on v1 (unchanged skill).

## Round 3 — skill v1 (stability check) + a new QUALITY dimension

**Result: PROVEN, 8/8 objective assertions, 0 repairs, 0 Go reads** — third
consecutive clean run, so the v1 *correctness* floor is real, not a lucky sample.
The record false-positive note (R1-1) and the emit-proof/ignore route (R1-2/3) were
again named as decisive in `skill_callouts`. 11.8 min / 148K tokens (higher than
round 2 because this run hit the `detail` completeness plateau + a self-inflicted
dirty bootstrap seed + an action-type rename — none a conform repair).

Minor friction (no skill change):
- **R3-1 environment** — completeness plateaued at 92–98% because the AWX 404/error
  envelope field `detail` was advertised but unmodeled; routed to
  `ignore_server_fields` (legit server-owned envelope). Correct per skill.
- **R3-2 environment** — `bootstrap --response` rejected a seed that still had a
  `curl -w 'HTTP 201'` trailer (`invalid character H after top-level value`).
  Self-inflicted dirty seed; bootstrap correctly rejected malformed JSON. *(Tiny
  optional skill note candidate: a `--response` seed must be pure JSON — strip curl
  status/headers. Deferred — low value, self-correcting.)*
- **R3-3 skill (worked)** — the Terraform action id is mechanically
  `dynamic_<type>_<verb>`, so to get `aap_workflow_job_launch` the contract `type`
  must be `aap_workflow_job`. terraform-usage.md made the fix obvious; the agent
  renamed and re-validated. No gap.

### R3-Q (the important one) — CONTRACT QUALITY: settable knobs green-washed into `ignore_server_fields`

**high | skill (+cli_engine contributing factor).** A new quality analyzer
(`harness/quality_analyze.py`) measured attribute richness against the AWX
ground-truth settable-field surface (`OPTIONS …/POST`). Across rounds 2 **and** 3,
every verbose resource is PROVEN + 100% complete but **exposes a fraction of the
optional inputs the API accepts**:

| contract | optional attrs exposed | settable fields dumped to `ignore_server_fields` | optional-input coverage |
|---|---|---|---|
| `job_template` | ~2–3 | **36–37** (`limit`, `verbosity`, `timeout`, `extra_vars`, `job_tags`, `skip_tags`, `forks`, `diff_mode`, all `ask_*_on_launch`, `survey_enabled`, `become_enabled`, …) | **0.12–0.14** |
| `inventory` | ~1–2 | 3–4 (`host_filter`, `kind`, `variables`, …) | 0.20–0.40 |
| `host` | ~2 | 1–2 | 0.50–0.75 |
| `organization` | ~2 | 1 | 0.67 |

AWX `job_template` POST accepts **43 settable fields (1 required, 42 optional)**;
the contract ships ~6 attributes and buries the rest. The result conforms, the
`terraform apply` works, and completeness reads 100% — but the resource can't
configure most of the API. This is **completeness green-washing**, and it is the
default the skill *induced*: the emit-proof 100% gate + "route the envelope to
`ignore_server_fields`" make ignoring the cheap path.

- **Skill fix (v2):** `ignore_server_fields` is server-*owned* output only. Before
  ignoring a field, ask "does the API accept it as a create/update input?" — if yes
  it's a practitioner knob and must be an `optional` attribute, not ignored.
  Green-washing called out by name in the completeness step, the bootstrap
  `--response` line, the emit-proof step, and "Done means". (+40 lines, generic.)
- **cli_engine candidate:** `completeness`/`--emit-proof` count *modeled* and
  *ignored* fields identically toward 100%, so the gate gives no credit for modeling
  a settable field as `optional` over ignoring it — it actively rewards the thin
  contract. Upstream improvement: warn (or separately score) when a field present in
  the **request schema** (OpenAPI request body / `OPTIONS` POST) is parked in
  `ignore_server_fields` — "you ignored N settable inputs." That would make the gate
  measure quality, not just coverage.

### R3-Q2 — over-`computed` optional attributes (quality)

**med | skill.** The agent marked `description` (and other optionals)
`optional: true, computed: true`. For `description` that is *correct* — AWX returns
`""` when you omit it (`OPTIONS default: ''`, verified by a create probe), so without
`computed` an unset description is a perpetual diff. **But the general habit is a
quality regression:** `computed` on an optional input the server leaves null/absent
when omitted silently suppresses Terraform drift detection on a real input. The
distinguishing test is "if I omit it on create, does the server supply a non-null
value?" — yes ⇒ `optional+computed`; no ⇒ `optional`-only. *Skill fix (v2):* a
"Get these right up front" bullet plus a tightened completeness clause — mark
`computed` only for server-*supplied* values, and let the CLI's
`promote_to_optional_computed` hint (which fires on exactly the server-defaulted
fields) decide, instead of pre-marking everything computed. (This also corrected a
too-loose "…or echoes it" phrase introduced earlier in the same v2 pass.)

### R3-A — terraform apply cleanliness (answering "is apply clean?")

`terraform apply` completes cleanly + idempotently every round: round 2/3 first-try
`Apply complete! Resources: N added … Actions: 2 invoked` → second plan `No changes`.
Round 1 only: an early `plan` threw `Error: invalid connection` on two contracts
which the agent fixed before the successful apply (transient, self-resolved). The
`Provider development overrides are in effect` line is the expected `dev_overrides`
notice. The launched job's *playbook* later shows `failed` in AWX (a brand-new
job_template with no real project content) — downstream of apply, outside the launch
action's assertion (the launch POST returns 201 + job id).

## Round 4 — skill v2 (validating the quality fix)

**Result: PROVEN; objective 7/8** (the one miss is a v2-induced data-source
regression, below). The quality fix **worked dramatically on resources** and the
over-`computed` concern did **not** materialize:

| contract | optional-input coverage v1 → **v2** | settable dumped → | over-computed |
|---|---|---|---|
| `job_template` | 0.12 → **0.93** | 37 → **3** | **0** (all 37 opt+computed have a real AWX default; 2 kept optional-only) |
| `host` | 0.75 → **1.0** | 1 → **0** | 0 |
| `inventory` | 0.40 → **0.80** | 4 → **1** | 0 |

The agent named the rules: *"completeness/green-washing rule — modelled all 40
settable job_template knobs as optional+computed instead of dumping settable fields
into ignore_server_fields"* and *"'computed is for server-supplied values' … mark
every server-defaulted optional optional+computed."* **Computed-precision verified
objectively:** every `optional+computed` field on `job_template` has a non-null AWX
`OPTIONS` default, so 0 are over-computed — the v2 rule is precise, not a blanket.

New findings:

- **R4-1 high | skill (v2 over-generalization → fixed in v3)** — *the green-washing
  rule was applied too broadly and regressed the read-only data source.* The DS
  shipped 7 attributes, **0 `ignore_server_fields`**, and stalled at **12.5%**
  completeness (was 100% in rounds 1–3). The agent read "don't route fields to
  ignore_server_fields" as universal, but a DataSource/Ephemeral is **read-only —
  it has no settable inputs**, so ignoring its non-projected envelope to reach
  completeness is legitimate. *v3 fix:* scoped the guard to **settable inputs
  (resources)**; for read-only kinds, model the useful computed outputs and ignore
  the rest of the envelope — don't leave it stuck low. (A good example of why we
  validate each edit: a correct rule, over-generalized, caused a new failure.)
- **R4-2 med | skill (recurring) → fixed in v3** — *action `type`/`verb` naming.*
  The Terraform action id is `dynamic_<type>_<verb>` by concatenation, so
  `type: awx_job_launch` + verb `launch` registers as
  `dynamic_awx_job_launch_launch`, and the first `plan` fails "no action schema for
  dynamic_awx_job_launch" *after* a record. **Recurred in rounds 3 and 4** (each cost
  a rename + re-record + re-plan). terraform-usage.md states the mapping but not the
  actionable authoring step. *v3 fix:* a "Get these right up front" bullet — split
  the desired action name at the trailing verb, put the stem in `type`
  (`awx_job_launch` → `type: awx_job`, verb `launch`). **Mild cli_engine angle:** the
  engine could detect `type` already ending in `_<verb>` and warn at load.
- **R4-3 environment** — a `record` retry hit "cassette path already exists" after
  the agent's own stdout-pipe parser errored on the first (successful) record;
  resolved with `--force`. CLI behaved correctly (valid stdout JSON, advisory stderr,
  no-clobber guard). Not actionable. (Echo of R2-1: keep stdout and stderr separate.)

**Harness note:** the grader's line-based `kind:` reader misread one resource
(`kind=""`) and under-counted resources; switched it to PyYAML. Re-grade: 4/4
resources, 7/8 overall (only the DS-completeness regression).

## Round 5 — skill v3 (validating both v3 fixes)

**Result: PROVEN, objective 8/8.** Both v3 fixes confirmed working, named in
`skill_callouts`:

- **Data-source regression fixed (R4-1):** DS completeness **12.5% → 100%**, now
  modeling **15** computed outputs (was 6–7). The scoped green-washing rule let the
  agent ignore the read-only envelope to reach completeness while enriching outputs.
- **Action naming fixed (R4-2):** *"action-id concatenation rule … avoided the
  `dynamic_awx_job_launch_launch` plan-time dead-end for both actions"* — clean first
  try, no rename/re-record (vs rounds 3 & 4 which each paid for it).
- **Resource optional-coverage retained:** `job_template` 0.93, `host` 1.0,
  `inventory` **1.0** (up from 0.80), with precise computed marking (`inventory` has
  1 `optional`-only + 4 `optional+computed`).

Friction:
- **R5-1 cli_engine (recurring, expected)** — the `record` example-vs-update_to
  false-positive warning (R1-1) fired again on every resource; the skill note
  neutralized it. Re-confirms R1-1 is the top upstream item.
- **R5-2 environment** — AWX returns `host_filter: null` even when `""` is sent, so
  the inventory needed `carry_on_read` and host_filter out of the body (1 conform
  repair — the only repair in 5 rounds). `record --suggest` flagged it *before*
  conform. AWX-specific data shape; tooling handled it well.
- **R5-3 skill (self-inflicted, already covered)** — a YAML flow-mapping parse error
  (`did not find expected , or }`) from hand-rewriting the bootstrap draft with an
  unquoted `${...}/...` path. SKILL.md already warns to quote such paths; no edit
  needed (bootstrap output is valid by construction — the trap is hand-editing).

---

# Benchmark across the pass (objective)

| Round | Skill | Verdict | Objective | Conform repairs | Go reads | Tokens | Wall | `job_template` opt-cov | DS completeness |
|---|---|---|---|---|---|---|---|---|---|
| 1 | v0 | PROVEN | 8/8 | 0 | 0 | 134K | 8.7m | 0.12 | 100% |
| 2 | v1 | PROVEN | 8/8 | 0 | 0 | 113K | 9.5m | 0.12 | 100% |
| 3 | v1 | PROVEN | 8/8 | 0 | 0 | 148K | 11.8m | 0.14 | 100% |
| 4 | v2 | PROVEN | 7/8 | 0 | 0 | 140K | 12.4m | **0.93** | 12.5% (regress) |
| 5 | v3 | PROVEN | 8/8 | 1* | 0 | 140K | 11.4m | **0.93** | **100%** |

\* the single round-5 repair is the AWX `host_filter` data-shape quirk, surfaced by
`record --suggest` pre-conform — not a skill/CLI defect.

**Net of the pass:** correctness held at the ceiling throughout (PROVEN, 0 Go reads).
The durable wins are **quality**: `job_template` optional-input coverage **0.12 →
0.93** with **0 over-computed**, data source outputs **6 → 15**, and two recurring
authoring dead-ends (action `type/verb`, emit-proof confusion) removed. Skill grew
v0→v3: **461 → 547 lines (+86)**, all generic.

---

## Round 6 — skill v3 (RESUMED, re-baselined on the *fixed* CLI build)

**Result: PROVEN, objective 8/8, completeness 100% on all 4 resources + the DS,
both launches (job 199, workflow job 200), idempotent replan, 1 conform repair, 0
Go reads.** 12.4 min / 168K tokens. The maintainer reported the blocking CLI items
were fixed; this round is the clean **v3-on-fixed-stack baseline** that isolates the
CLI-fix effect from any skill edit *before* touching the skill. Binary under test:
`~/.local/bin/agentprovider` (rebuilt 13:39, distinct sha from the prior repo-root
build); the repo-root `terraform-provider-dynamic` was synced to the same build so
Terraform's `dev_overrides` exercises the fixed engine too.

**Calibration — what the fixed binary actually does (ground-truthed, not assumed):**

| item | reported fixed | observed this build | evidence |
|---|---|---|---|
| R1-1 record re-record false-positive | yes | **STILL FIRES** verbatim on every resource | raw run-log L34–35 (`"…will fail conform on re-record. Move … into conformance.expect"`) + skill_callouts[0] |
| R3-Q completeness flags settable-in-ignore | yes | **not observed** — `completeness` returns 100% even with `--metadata <OPTIONS.json>` (43 POST fields) fed; `job_template` still parks 3 settable knobs in `ignore_server_fields` | `quality_analyze` + direct `completeness --base-url --metadata` probe (no settable/ignore key in output) |
| R4-2 warn at load on `type` ending in verb | yes | **not at `validate`** (valid=true, empty diagnostics for `type: awx_job_launch` + verb `launch`); may fire at the record/plan load path, untested | offline `validate` probe on `/tmp/probe_verb.yaml` |
| CLI-A numeric `default:` accepted | yes | **CONFIRMED FIXED** — `validate` accepts a `number` attr with `default: 3` (previously load-rejected) | offline `validate` probe on `/tmp/probe_numdefault.yaml` |

Only **CLI-A** is observably active in this binary; **R1-1 is definitely still
firing** (in the real eval, exact text).

**SOURCE-LEVEL VERIFICATION (settles the "which build" question).** Hunted every
`agentprovider` binary under `$HOME`: the newest anywhere is `~/.local/bin`
(13:39), which equals current `main` HEAD code in
`~/git/research-dynamic-provider/terraform-provider-dynamic` (the only later commit,
`98066f8` @ 14:09, is a chore — "adopt optimized skill + refresh dev_overrides
provider binary", no engine code). Grepping the source proves what landed:

- **R1-1 — never fixed.** The warning string still lives at
  `cli/agentprovider/record.go:445`; the surrounding loop still does
  `state = updated` (line 530) before the example/observed comparison → still
  compares to the **post-update** value. No fix commit.
- **R3-Q — never implemented.** **Zero** occurrences of `settable` in the Go
  source; `completeness` has no settable-vs-`ignore_server_fields` cross-check.
  (My `--metadata OPTIONS` probe returning 100% is therefore expected, not a
  mis-invocation.)
- **R4-2 — never implemented.** No `_launch_launch` / type-ends-in-verb detection.
- **CLI-A — fixed** (commits `0f00180`/`0bebb75` "support/prove numeric static
  defaults") — matches the offline `validate` probe.

**What actually shipped this round = CF-1…CF-6 + numeric defaults (CLI-A)**, not
R1-1/R3-Q/R4-2 (commit log: `240c637` CF-1 identity-suggestion suppression on
actions, `8f85acd` CF-2 short-value redaction, `829fad4`/`b6672a6` CF-3 transport
hint, `061aed1` CF-4 by-id advisory, `57e1bab`/`d182fbb` CF-6, plus the numeric
defaults feature). So R1-1/R3-Q/R4-2 **stay open CLI-side** and their skill
mitigations remain **load-bearing** — v4 keeps all three. **CF-1 and CF-2 landing**
means the skill's soft workaround notes for those (`record --suggest` identity
suggestion on actions; redactor short-value over-match) are now **trim candidates**
— defer to iteration-7's run-log evidence before cutting.

### New friction this round

- **R6-1 high | skill (actionable v4 edit)** — *`update.body` ↔ `update_to`
  asymmetry.* The only repair this round. `awx_organization` modeled
  `default_environment` as an optional attribute and listed it in `update.body`;
  `record` sent it as `null` (present-as-null projected state), but `update_to`
  **omitted** it, so `conform` built a PATCH body with fewer keys → byte-replay miss
  (`no recorded interaction for PATCH …/92/`) on `update_then_read_reflects`,
  `second_apply_is_noop`, `id_stable_across_update`. The skill's "`update_to`/
  `update.body` list *every* request-body attribute" rule covers **omitting a
  changed key**; it does not state the **inverse**: any attribute present in
  `update.body` must also appear in `update_to` with a value (or be dropped from
  `update.body` if never exercised), because `record` sends it (null included) and
  `conform` rebuilds the body from `update_to`'s keys. *Generic; one sentence
  pre-empts the loop.*
- **R6-2 med | skill (recurring misattribution → preventable)** — the agent filed
  the `conform --mutation-check` status banner (`mutation check: targeted invariants
  bite N/M`) as a `cli_engine` stdout-hygiene bug. **Ground-truth re-verified: stdout
  is pure JSON; the banner is on stderr** (`conform … --mutation-check 2>/dev/null |
  python -c json.load` parses clean). This is the *same* misattribution as R2-1 — it
  has now cost two passes. The skill says "JSON on stdout by default" but never says
  the `--mutation-check` banner is stderr-only, so a careful author re-discovers it
  and wastes a step switching to `--format text`. *Skill note: parse stdout alone,
  never `2>&1`; the status banner is stderr.* (Not a CLI defect — verified.)
- **R6-3 low | skill (doc precision)** — `--emit-proof` writes
  `<type>.proven.json` (the contract filename with `.yaml` **replaced**, e.g.
  `awx_organization.proven.json`), not `<contract>.yaml.proven.json`. The skill's
  `<contract>.proven.json` shorthand is ambiguous about extension handling; the agent
  briefly looked in the wrong place. *One-word clarification.*
- **R6-Q med | skill (+cli_engine: R3-Q can't help here)** — *residual green-washing
  on `job_template`:* `quality_analyze` (vs AWX `OPTIONS`/POST, ground truth) shows
  3 API-settable fields parked in `ignore_server_fields` — `execution_environment`,
  `webhook_credential`, `prevent_instance_group_fallback`. The agent rationalized the
  FK-reference ids as "true server-owned." They are **settable inputs** (accepted in
  POST). Because the R3-Q gate did **not** flag them (see calibration table), the
  prose guard is the only line of defense. *Skill sharpening: FK/reference ids
  (`*_credential`, `execution_environment`, `default_environment`, `*_environment`)
  are practitioner-settable — model `optional`, don't classify as server-owned.*
  Opt-input coverage otherwise strong: host/inventory/org 1.0, `job_template` 0.93.
- **R6-4 environment** — first `terraform plan` hit empty `AWX_PASSWORD` until `.env`
  was sourced from repo root. Known harness artifact (relative password path); not
  skill/CLI-actionable.

### cli_engine items re-confirmed OPEN on this build

- **R1-1 still fires** (top upstream item, now 6 rounds running). If
  `~/.local/bin/agentprovider` is the intended fixed build, the fix did not land or
  did not address this warning. Skill mitigation **kept** (still load-bearing —
  named decisive in skill_callouts[0]).
- **R3-Q not demonstrable** via `completeness --base-url [--metadata OPTIONS]`; the
  settable-vs-ignore cross-check is either unwired to the live/metadata source or
  needs `--openapi`. Logged so v4 does **not** lean the green-wash guard on an
  unconfirmed gate.

---

## Round 7 — skill v4 (validating the four round-6 edits)

**Result: PROVEN, objective 8/8, 0 conform repairs (was 1), 0 Go reads, 11.4 min /
132K tokens** (leaner than the v3 baseline's 168K — the dead-ends the v4 notes
removed). All four v4 edits confirmed working, each named in `skill_callouts`:

- **R6-1 (update.body↔update_to symmetry) → 0 repairs.** The v3 baseline's only
  repair was `default_environment` in `update.body` but omitted from `update_to`.
  This round the agent (run-log L30) modeled it `optional` and, *"not changed in
  update so kept out of update.body/update_to"* — the symmetry rule pre-empted the
  replay miss outright.
- **R6-Q (FK ids are settable) → resource green-washing resolved.**
  `job_template` settable-dumped **3 → 0**, opt-input coverage **0.93 → 1.0**:
  `execution_environment`/`webhook_credential`/`inventory` now modeled as `optional`
  FK numbers (run-log L46: *"none routed to ignore_server_fields — they name related
  objects … practitioner knobs"*). host/inventory/org stay 1.0/0-dumped.
- **R6-2 (stdout pure JSON / stderr banner) → no misattribution.** The agent parsed
  stdout alone and did **not** re-file the mutation-check banner as a CLI bug (it
  did in round 6). `skill_callouts`: *"parse-stdout-alone … JSON parsed from stdout
  without 2>&1."*
- **R6-3 (sidecar filename)** — no sidecar-location confusion this round.

### Findings

- **R7-1 ~~skill regression~~ → harness bug (fixed in `quality_analyze.py`).**
  `quality_analyze` flagged the `awx_job_template_lookup` **DataSource** with 29
  "settable knobs dumped to ignore_server_fields." **False positive:** a read-only
  DataSource has **no settable inputs** — the `ask_*_on_launch` fields are settable
  on the *resource*, but on a by-id *lookup* they are computed outputs, legitimately
  ignored (the skill's read-only carve-out, which the agent applied correctly —
  `skill_callouts[4]`). The script was comparing the DS against the sibling
  *resource's* `OPTIONS/POST` surface. Tell-tale: round-6's DS (`..._by_id`, suffix
  not stripped → no endpoint match → "—") wasn't flagged; round-7's (`..._lookup`,
  stripped → matched) was — a pure naming artifact. **Harness fix:** skip the
  settable-coverage check for `DataSource`/`Ephemeral`/no-create kinds (like actions
  are skipped). Re-measured: DS reads "—", all 4 resources opt-cov 1.0 / 0 dumped.
  The DS actually *improved* (16 computed outputs vs 8 in round 6). **Not a skill or
  CLI issue.**
- **CF-1 CONFIRMED FIXED in-run → skill trim candidate (v5).** `record --suggest`
  proposed **no** `identity.response_field` on either action (run-log L61, L66);
  it appeared only on the by-id data-source read (where identity is appropriate,
  L53). So the skill's *"--suggest may propose identity.response_field on an
  action-only contract — ignore it"* note now describes behaviour the CLI suppresses
  (`240c637`). v5 trims it to a lean generic "`--suggest` is resource-tuned" line.
- **R1-1 still fires** (cli_engine, open) — ignored per skill on all 4 resources;
  mitigation remains load-bearing.
- **environment** — `.env` relative-password sourcing (known); and the second plan
  showed the data source's computed `status` reflecting a live AWX job-status change
  (`never updated → failed`), which is correct read-only DS behaviour (all managed
  resources reported no changes), not drift.

**v5 edit (one, generic, lean-because-the-CLI-improved):** trim the now-dead CF-1
`--suggest` identity-on-action workaround to a single generic line. CF-2 note **kept**
(not exercised this round; the fix narrows but doesn't eliminate short-value
over-match, and the note is defensive). Validating as round 8.

## Round 8 — skill v5 (CF-1 trim) + the key VARIANCE finding

**Result: PROVEN, objective 8/8, 1 conform repair, 0 Go reads, 11.5 min / 139K
tokens.** The v5 trim itself is validated; the round's real value is exposing a
quality-variance problem.

- **CF-1 trim validated.** `record --suggest` proposed **no** `identity.response_field`
  on either action (empty list) — the v5 generic `--suggest`-is-resource-tuned line
  caused no failure. Safe trim.
- **R8-1 high | skill + cli_engine (THE finding) — green-wash quality is
  high-variance; prose can't stabilize it.** `quality_analyze`: `job_template`
  **opt-cov 0.48, 22 settable dumped** — the agent parked the 16 `ask_*_on_launch`
  boolean toggles (+6 more) in `ignore_server_fields`. Round 7 (v4) under the
  *identical* green-wash guidance got **opt-cov 1.0, 0 dumped**. So v4↔v5 (same text)
  = **0 vs 22 dumped**. The R6-Q FK rule held both times (the 3 FK ids are modeled in
  v5); the swing is entirely the **behavior-toggle family**, which the skill never
  names. *Two consequences:* (a) **skill v6** — extend the settable examples to name
  `ask_*`/`enable_*`/`allow_*`/`*_on_launch` flags present in the request schema as
  settable knobs; (b) **R3-Q's priority rises** — only a mechanical gate makes quality
  *reproducible*; prose is sample-dependent on a verbose object.
- **R8-2 med | skill variance (R6-1 reactive vs preventive)** — the
  `default_environment` `update.body` trap **recurred** (1 repair). The R6-1 symmetry
  note *caught and fixed* it (agent named it), but this sample hit-then-fixed rather
  than pre-empting (round 7 pre-empted, 0 repairs). The rule works; whether it's used
  preventively is sample-dependent. Candidate v6 micro-refinement: phrase R6-1 as
  "don't put an unchanged optional in `update.body` at all" (preventive framing).
- **R8-3 low | skill (e-feedback)** — with the CF-1 specific gone, the agent noted
  the generic `--suggest` line doesn't name the *action* shape (on an action,
  `--suggest` dumps the whole read payload as `unmodeled_fields`). It inferred it
  fine (low-by-design guidance covers the spirit). Marginal; optional v6 clarifier.
- **R1-1 still fires** (cli_engine, open); **env** — `.env` password + DS `status`
  live-drift (correct DS behaviour), as prior rounds.

**v6 plan:** (1) name the behavior-toggle family in the green-wash guard (targets the
22-dumped regression); (2) optionally reframe R6-1 preventively. Validate across **≥2
samples** (variance demands it), or accept that R3-Q is the durable fix and stop the
prose chase.

## Round 9 — skill v6 (toggle-family edit), variance sample 1 of 2

**Result: PROVEN, objective 8/8, 2 conform repairs, 0 Go reads, 13 min / 158K
tokens.** `job_template` **opt-cov 1.0, 0 dumped** (43 settable modeled, 13
server-owned ignored) — the **opposite of v5's 0.48/22**. The agent named the v6
edit decisive: *"the ask_*_on_launch / enable_* / *_enabled toggle family are
SETTABLE knobs … must be modeled optional(+computed), not dumped … reaching 100% the
honest way."* Sample 1 of the 2-sample variance test = the **good** outcome.

- **R9-1 med | cli_engine (NEW, well-reasoned) — `optional_default_consistency`
  offline gate misses sent-null-then-canonicalized.** `webhook_service` was modeled
  `optional`-only (AWX `OPTIONS` says `default: None`), but the live create
  canonicalizes the sent `null → ""`. The offline gate **passed** because the field
  was *present* in the recorded create body (sent as null) — the gate only fires on
  fields **omitted** from the create body, so a modeled-optional sent-as-null that
  the server returns non-null slips past it and surfaces only at `terraform apply`
  (`Provider produced inconsistent result after apply: webhook_service was null,
  server returned ""`). Fixed by `optional+computed` + re-record. **Fix:** the
  offline gate should also flag *null-in-create-body → non-null-in-response* (a
  canonicalization), not just *omitted → defaulted*. *(Minor skill-note candidate,
  deferred as overfit-risk: a nullable string optional whose server canonicalizes
  `null→""` needs `optional+computed`; but the author can't know that from `OPTIONS`
  alone — the durable fix is the gate.)*
- **R9-2 med | skill variance (R6-1 recurred again, recovered)** — the
  `default_environment` `update.body` trap recurred (1 of the 2 repairs); the R6-1
  symmetry note diagnosed it and the agent authored the next 3 resources with zero
  update repairs. Same hit-then-fix variance as round 8; rule is adequate (already
  states the preventive form), recurrence is sample-level.
- **R1-1 still fires** (cli_engine, open), ignored per skill. **env** — `.env`
  password path (known).

## Round 10 — skill v6 (toggle-family edit), variance sample 2 of 2

**Result: PROVEN, objective 8/8, 2 conform repairs, 0 Go reads, 13 min / 141K
tokens.** `job_template` **opt-cov 1.0, 0 dumped** — **matches sample 1**. The agent
modeled all 17 `ask_*_on_launch` + `survey/become/diff_mode/allow_simultaneous/
use_fact_cache/force_handlers/prevent_instance_group_fallback` as `optional+computed`
(47 attrs modeled, only the server-owned envelope ignored), crediting the v6 edit:
*"the green-washing guidance on this exact `ask_*`/`enable_*`/`*_on_launch` family
was explicit and unambiguous … directly named this as the biggest trap."*

**→ v6 variance test: 2-for-2 at opt-cov 1.0 / 0 dumped** (vs v5's lone 0.48/22).
The toggle-family edit converted the green-washing swing into a stable high-quality
outcome. Not full determinism (prose still needs the agent to apply it; R3-Q gate is
the guaranteed fix), but a decisive improvement.

- **R10-1 = R9-1 recurred (consistent, not variance).** `webhook_service` again cost
  a repair on `job_template` (server returns `""` vs `OPTIONS default: null`). Both
  v6 samples hit it → it is a **reproducible** field-shape cost, reinforcing R9-1.
  (This sample classified it `environment` — AWX metadata-vs-echo inconsistency;
  sample 1 classified it `cli_engine` — offline-gate gap. Both framings hold; the
  durable fix is the offline gate flagging null→non-null canonicalization.)
- **R10-2 low | cli_engine (recurring, ~R4-3)** — a `record` re-run without `--force`
  failed `cassette path already exists`, and the *next* conform (against the stale,
  un-overwritten cassette) looked like a contract regression. Resolved with
  `--force`. Already-known no-clobber behaviour; the agent suggests a one-line
  conform-replay hint (`cassette unchanged — pass --force`). Low.
- **R10-3 = R6-1 recurred** (org `default_environment`), recovered via the symmetry
  note. Same hit-then-fix variance as rounds 8–9.
- **R1-1 still fires**, ignored per skill. **env** — `.env` password path.

---

# ✅ PASS COMPLETE (2026-05-29, rounds 6–10) — skill v3→v6; correctness converged, quality stabilized

**5 resumed rounds on the fixed CLI build. Every round PROVEN, objective 8/8, 0
engine-Go reads.** Skill **v3 (547 lines) → v6 (582, +35, all generic)**.

**Wins this pass:**
- **R6-1** (update.body↔update_to symmetry) — removed the v3 baseline's repair.
- **R6-Q + v6 toggle-family** — `job_template` green-washing: v3 baseline 3 dumped /
  v5 22 dumped (variance) → **v6 2-for-2 at 0 dumped, opt-cov 1.0** (all 43 settable
  modeled). The headline quality result, validated against sampling variance.
- **R6-2/R6-3** — killed a recurring stdout/stderr misattribution and a sidecar-name
  ambiguity (tokens 168K→132K on the v3→v4 step).
- **CF-1 trim** — first "skill gets leaner because the CLI improved" edit (CF-1 fixed
  upstream, confirmed in-run).

**Open CLI/engine items (durable fixes, see `remaining_to_fix_2026-05-29.md`):**
R1-1 (re-record false positive, top priority, fires every round), R3-Q (green-wash
scoring — *raised priority*: prose can't make quality reproducible, only the gate
can), R4-2 (`_verb` double-suffix), R9-1 (offline `optional_default_consistency`
misses null→canonicalized), CF-3 residual (bootstrap flag emit), R10-2 (conform
stale-cassette hint).

**Convergence:** correctness + efficiency at ceiling; quality stabilized by v6.
Further *guaranteed* quality gains require the R3-Q gate to land — not a skill edit.
Natural stopping point.

---

## (superseded) RESUMED banner — rounds 6–9

Round 6 re-ran the **v3 skill on the rebuilt CLI** as a clean baseline. Of the four
items reported fixed, only **CLI-A** (numeric `default:`) is observably active;
**R1-1 still fires** in the real eval. The skill is still at **v3**; v4 edits below
are driven by the *new* round-6 findings (R6-1/2/3/Q), which are genuine generic
improvements independent of the CLI question.

**Planned v4 edits (all generic, evidence-backed):**
1. **R6-1** — add the `update.body`↔`update_to` inverse-symmetry sentence (every
   `update.body` attr must be valued in `update_to`, or dropped if never changed).
2. **R6-2** — one line: `conform`/`--mutation-check` keep stdout pure JSON; the
   status banner is stderr — parse stdout alone, never `2>&1`.
3. **R6-3** — clarify the proof sidecar is `<type>.proven.json` (`.yaml` replaced).
4. **R6-Q** — sharpen the green-wash guard: FK/reference ids are settable inputs.
5. **SKILL-D (optional, now CLI-A-enabled)** — prefer `optional + default:<val>`
   over `optional + computed` for *statically*-defaulted optionals (incl. numerics);
   reserve `computed` for dynamically server-supplied/canonicalized values. Held to
   low priority — its drift-detection benefit isn't conform-validatable in this
   harness, and v3's computed discipline already shows 0 over-computed.

**Kept (still load-bearing on this build):** the R1-1 mitigation; the action
`type`/verb split rule (R4-2 warning not confirmed); the prose green-wash guard
(R3-Q gate not confirmed).

---

# ⏸ Prior pause note (superseded by the RESUMED banner above) — original blocking list

Per the maintainer, iteration paused here until the `cli_engine` items landed. The
skill was at **v3**. Resume criteria were to (a) confirm the false-positive warning is
gone (drop or shrink the skill's R1-1 mitigation), and (b) re-measure whether a
quality-aware completeness gate changes authoring behavior. *(Round 6 above executed
this resume: R1-1 still fires, R3-Q not demonstrable on this build.)*

**Blocking CLI/engine candidates (priority order):**

1. **R1-1 — `record` false-positive "will fail conform on re-record" warning.**
   Fired on every CRUD resource, all 5 rounds. Root cause: compares
   `conformance.example` against the **last (post-update)** observed value instead of
   the **create-time** value, so any field changed in `update_to` trips it. Its
   suggested fix (move the field to `expect.not_null`) *weakens* `create_echoes_inputs`.
   **Fix:** compare against the create-phase observation (or suppress when the field
   appears in `update_to`). *Highest-noise, highest-value.*
2. **R3-Q — completeness/`--emit-proof` rewards thin (green-washed) contracts.** The
   100% gate counts *modeled* and *ignored* fields identically, so ignoring a
   settable input scores the same as exposing it. **Fix:** warn (or separately score)
   when a field present in the **request schema** (OpenAPI request body / `OPTIONS`
   POST) is in `ignore_server_fields` — "ignored N settable inputs." Makes the gate
   measure quality, not just coverage. (Skill v2/v3 mitigates by guidance only.)
3. **R4-2 — action `type` ending in `_<verb>` silently double-suffixes.**
   `type: awx_job_launch` + verb `launch` → `dynamic_awx_job_launch_launch`, failing
   only at `plan` after a record. **Fix:** warn at contract load when `type` ends in
   `_<declared-verb>`. (Skill v3 mitigates with the split-the-name rule.)
4. **CF-1 — `record --suggest` proposes `identity.response_field` on action-only
   contracts** (an action has no identity). Suppress for action-only contracts.
5. **CF-3 — `bootstrap` omits `allow_insecure`/`allow_private_host`** for an
   `http://`/RFC-1918 base_url; infer them at bootstrap so the SSRF guard doesn't
   first trip at `record`/`plan`.

**Non-issues (verified, do not re-file):** R2-1 stdout/stderr "mixing" — stdout is
clean JSON, prose is on stderr (and `record` warnings are also in the JSON
`warnings[]`). R5-2 host_filter, R4-3 cassette-exists-on-retry, R5-3 flow-mapping
quoting — environment/self-inflicted.

---

# Analysis: `computed` over-use on `awx_job_template` (AAP cross-compare)

**Question:** why does `awx_job_template.yaml` mark 37 settable fields
`optional: true, computed: true`? Cross-compared against the official
`ansible/aap` provider's `job_launch` action
(`registry.terraform.io/providers/ansible/aap/latest/docs/actions/job_launch`,
source `internal/provider/job_launch_action.go`).

**Finding: mostly correct/required, not over-use — with one real kernel of truth.**

1. **The AAP reference can't speak to the computed question.** `aap_job_launch` is a
   Terraform *Action* — its source confirms *"does not store state … creates a new
   job each invocation,"* and all 18 attributes are `Required`/`Optional`, **zero
   `Computed`** (an action has no state round-trip, so inputs are never computed).
   Our equivalent *action* (`awx_job_launch`) likewise uses **zero computed on
   inputs** — we match AAP exactly there. The 37 computed fields are on our
   `awx_job_template` **resource**, and the AAP provider has **no job_template
   resource** (it launches templates, doesn't manage them) — so there is no
   like-for-like reference.

2. **For a CRUD resource against AWX, `computed` is load-bearing.** The applied HCL
   sets 5 fields and leaves ~34 unset; AWX fills each with a server default and echoes
   it on read. The clean second-plan no-op only holds because those fields are
   `computed` (Terraform absorbs the server value). Plain `optional` → config `null`
   vs state default → perpetual diff → `second_apply_is_noop` fails at apply.

3. **Boundary tests (against the round-5 cassette + live AWX):**

   | experiment | result | meaning |
   |---|---|---|
   | `diff_mode` plain `optional` (no computed/default) | conform passes | conform-vs-cassette doesn't force computed (example *sets* the field) |
   | numeric `verbosity` with `default: 0` | **load-rejected** | numeric attrs cannot carry `default:` — computed is the only tool |
   | `diff_mode` `default: true` (≠ server `false`) | conform passes | `optional_default_consistency` not firing (all fields are set in `example`) |

   The forcing function is **apply-time perpetual-diff avoidance**, not conform.

4. **Field-class breakdown:**

   | class | ~count | can avoid computed? | verdict |
   |---|---|---|---|
   | numeric server-defaulted (`forks`,`verbosity`,`timeout`,`job_slice_count`) | 4 | **no** (`default:` rejected; plain optional perpetual-diffs) | computed **required** |
   | bool/string with static default (`diff_mode`, 16× `ask_*_on_launch`, `survey_enabled`, `extra_vars`/`limit`=`""`, …) | ~31 | **yes** (`optional + default:<val>` accepted) | computed **works, not ideal** |
   | always set in HCL (`job_type`,`playbook`) | 2 | n/a | harmless over-mark |

5. **The genuine kernel:** for the ~31 bool/string fields with a *known static*
   server default, `optional + default:<val>` is higher-fidelity than
   `optional + computed` — it **preserves drift detection** when the field is unset
   (computed silently absorbs server-side changes) and shows an explicit plan value
   instead of `(known after apply)`. We blanket-computed because nothing penalizes it
   (conform passes either way), the green-washing fix pushed modeling all settable
   fields, and `optional+computed` is type-agnostic and always apply-safe — the path
   of least resistance.

### Two candidates from this analysis

- **CLI-A (blocking-adjacent) | cli_engine** — *numeric attributes cannot carry
  `default:`* (rejected at load), so a numeric **server-defaulted** field (`forks`,
  `verbosity`, `timeout`, `job_slice_count`) is *forced* to `optional+computed` even
  when its default is a known static constant — losing drift detection with no
  alternative. **Fix:** allow numeric (and ideally collection) `default:`, or add an
  explicit `server_default: <val>` marker that satisfies `optional_default_consistency`
  while keeping the attribute drift-tracked. Pairs with R3-Q (both are about the
  engine steering authors toward lower-fidelity modeling). Add to the blocking list
  when CLI work resumes.

- **SKILL-D (deferred v4 candidate) | skill** — for a bool/string optional whose
  server default is a *known static* value, prefer `optional: true, default: <val>`
  over `optional: true, computed: true` to preserve Terraform drift detection;
  reserve `computed` for numeric server-defaulted fields (no `default:` available) and
  for values the server *computes* dynamically rather than statically defaults.
  Generic. **Deferred** — do not apply during the pause; revisit alongside the R3-Q2
  computed-precision guidance so the two stay consistent, and re-measure with the
  `quality_analyze.py` computed-precision check.
