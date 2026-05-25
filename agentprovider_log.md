# agentprovider skill — optimization log

Running log of **errors** and **potential improvements** observed while running 3
rounds of skill-creator optimization on the `agentprovider` skill.

- Eval task: `prompt.txt` (build a fresh AWX provider end-to-end against live AWX).
- Constraint: the skill must stay **generic** — AWX is only the test instance; no
  AWX-specific guidance is baked into `SKILL.md`. Fixes here are phrased as
  general patterns.
- Each entry tags whether it is an **engine/CLI** issue (worth reporting upstream,
  not an authoring failure) or a **skill** issue (the SKILL.md guidance could have
  prevented the friction).

Format per entry: `[round] severity | engine|skill | symptom → fix/insight`.

---

## Round 1 — baseline (skill v0)

**Result: PROVEN.** 7/7 contracts conform (non-empty invariants), `terraform apply`
succeeded (6 resources + 1 data source + 2 actions), idempotent second apply.
~7.3 min, 112K tokens, 72 tool calls. **0 engine Go-source dives** (regression
check vs prior optimization: held). 5 of 7 contracts conformed on the first
`conform`; only **1** genuine repair the whole run.

Errors / friction observed:

- **R1-1 high | skill** — *Action path-input collides with a computed output's
  API field.* `job_launch` failed contract load: `attributes "id" and "run_id"
  both map to API field "id"`. Cause: the action's path input was named `id`
  while a computed output mapped `field: id`. This was the **only** genuine repair
  in the run, it fails closed only at record/replay (costs a re-record), and it
  hits **any by-id action**. The worked example uses `pipeline_id` but never says
  *why* the input isn't `id`. → v1: added a "Get these right up front" bullet
  explaining the collision + the why (generic; `<resource>_id` naming).
- **R1-2 med | skill** — *Action/ephemeral completeness is low by design.* Action
  contracts reported 8.6% / 12.8% completeness; the completeness section is written
  for resources and doesn't say a low number is expected for a verb that models
  only inputs + a few outputs. Risk: an author chases a meaningless percentage or
  points `--min-completeness` at an action. → v1: added a note that completeness is
  a resource/data-source gate; judge actions by `action_returns_expected`.
- **R1-3 med | skill** — *`--response` drafts are mostly noise; `--ignore`/`--alias`
  are OpenAPI-only.* For a verbose API, a `--response` seed mirrors the whole
  payload (`related`, `summary_fields`, timestamps), so all 4 CRUD drafts were
  rewritten, not "repaired," and `--ignore` (which looks usable) doesn't apply to
  `--response`. → v1: expectation-setting note in the bootstrap step.
- **R1-4 low | skill** — *identity-`string` vs FK-`number` needs cross-referencing.*
  The author wanted a one-line "identity token → string, integer FK in a path →
  number" rule of thumb. → v1: appended a contrast clause to the identity bullet.
- **R1-5 low | skill** — *not every completeness `missing` field is worth modeling.*
  A `detail`-type field appeared `missing` on every CRUD completeness (an
  error/delete response-shape artifact). → v1: folded a "weigh by practitioner
  relevance, not count" clause into the completeness guidance.
- **R1-6 info | engine** — first `record` against a plaintext/local target fails the
  SSRF guard until `allow_insecure`/`allow_private_host` are hand-added (bootstrap
  doesn't emit them). Already covered by the skill's "Get these right up front";
  no change needed beyond what exists.
- **R1-7 info | engine** — AWX-state noise (a name-collision 400 from leftover
  objects; a 500 launching a zero-node workflow). Not skill-actionable; handled by
  the harness cleaning AWX between rounds.

_Reference-file ideas (not applied — task scopes edits to SKILL.md; logged for the
maintainer): mirror R1-1 into `references/contract-format.md`'s action example, and
R1-2 into `references/cli-loop.md`'s completeness section._

## Round 2 — skill v1

**Result: PROVEN. 0 repair-hint loops across all 7 contracts** (down from 1 in
round 1 — the action-collision repair was eliminated). Faster: ~6.4 min (vs 7.3),
107.5K tokens (vs 112K), 71 tool calls. 0 Go-dives held. All 7 conformed on the
first `conform`.

**v1 improvements verified working** (the run called them out by name):
- *Action id collision warning* → "decisive — naming inputs `*_template_id` from the
  start avoided the `both map to API field "id"` load error." (R1-1 fixed.)
- *Action completeness low-by-design* → "didn't panic at 6.9%/10.3%, didn't gate
  `--min-completeness` on actions, didn't model 50+ irrelevant fields." (R1-2 fixed.)
- *`--response` rewrite-heavy* → "turned a potential multi-cycle discovery into one
  up-front rewrite." (R1-3 fixed.)

New / residual friction:

- **R2-1 med | skill** — *A by-id data source or action needs its lookup/target
  object to EXIST at record time.* `record` hits the live API, so the id a data
  source looks up (and the `${...}_id` an action targets) must point at a real
  object; the agent had to create a fixture object first. The skill never states
  this prerequisite. Generic (any "look up existing X by id" data source, any by-id
  action). → v2: add a record-step note to create a throwaway fixture first.
- **R2-2 low | engine→skill** — *`record --suggest` is resource-tuned; on an
  action-only contract it proposes an `identity.response_field` you don't want.*
  Harmless but noisy. → v2: one clause telling authors to ignore that suggestion on
  action-only contracts.
- **R2-3 low | engine→skill** — *the cassette redactor matches by substring, so a
  short/common credential value (here the username) shows as a "redaction hit"
  against unrelated field-name text.* It's conservative over-matching, not a leak —
  but the skill tells authors to review the cassette, so it should say how to read
  such a match. → v2: append a reassurance to the redaction bullet.

## Round 3 — skill v2

**Result: PROVEN. 0 repair-hint loops across all 7 contracts** (held from round 2).
Lowest token use of the three runs (99.9K; vs 112K / 107.5K), ~7.2 min, 75 tool
calls, 0 Go-dives. All 7 conformed on the first `conform`. 6/6 objective
assertions; password in 0/32 captured files.

**v2 improvements verified working** (run confirmed by name):
- *by-id fixture-at-record-time* → "set the right expectation for the data source
  (org 1) and the workflow action (wfjt 56)." (R2-1 fixed.)
- *`--suggest` over-suggests identity on actions* → "both action records emitted
  exactly this; ignored without second-guessing." (R2-2 fixed.)
- *redactor over-match* → "cheap insurance; least-exercised with Basic auth (creds
  in header, redacted cleanly)." (R2-3: useful, low-exercise.)

New / residual friction (skill is at the noise floor — only refinements remain):

- **R3-1 med | skill** — *The "re-record after editing example/body" rule was stated
  too absolutely.* Editing a value that is only an **assertion target** (an action's
  expected computed *output*, a `conformance.expect` matcher) changes no replayed
  request, so it needs no re-record — only changes to a replayed body/path do. The
  agent inferred this and skipped 2 needless live job launches. → v3: sharpened the
  rule with the request-vs-assertion distinction + the why. (This is the one v3
  change — a precision refinement of an existing rule, not a new rule.)
- **R3-2 low | env (not skill)** — first `terraform apply` hit `400 ... already
  exists` from leftover objects of a prior run. This is an artifact of the eval
  harness reusing one live AWX, not a real-world skill gap (a user applying to their
  own AWX won't hit it). _Logged, deliberately NOT added_ — adding an apply-preflight
  rule would be bloat for an environmental edge case the run itself tagged "not a
  skill issue."
- **R3-3 low | skill (declined)** — suggestion to add a numeric completeness heuristic
  ("15–25% is normal for verbose objects"). _Declined_: the v1 edits already say
  "weigh by relevance, not count" and "actions are low by design"; a hard percentage
  risks overfitting and contradicts the generic, dynamic completeness model. Logged
  for the maintainer to consider as a reference-file example instead.

**Decision:** v3 is the final version — a single precision refinement. Rounds 2 and
3 both hit 0 repairs / PROVEN / 6&6 assertions, so further rule additions would add
length without reducing friction (the round-3 run explicitly found "nothing felt
like dead weight," i.e. no bloat to cut and no gap to fill beyond R3-1).

---

## Summary of skill changes by round

| Round | Version | Key generic improvements applied |
|---|---|---|
| 1 | v0 → v1 | (1) action input/output API-field collision warning + why; (2) completeness is low-by-design for actions/ephemerals; (3) `--response` drafts are rewrite-not-tweak & `--ignore`/`--alias` are OpenAPI-only; (4) identity→string vs FK→number rule of thumb; (5) weigh completeness `missing` by relevance not count. +28 lines. |
| 2 | v1 → v2 | (1) record-step note: by-id data sources & actions need their lookup/target object to exist at record time (create a fixture first); (2) `--suggest` is resource-tuned — ignore its `identity.response_field` hint on action-only contracts; (3) redaction is conservative substring matching — a short credential value may over-match harmlessly, verify the real secret is absent. +13 lines. |
| 3 | v2 → v3 | Sharpened the re-record rule: re-record only when you change a **replayed request** (body/path input); a value that is only an **assertion target** (action expected output, `expect` matcher) needs no re-record — just re-run `conform`. Precision refinement of an existing rule. +5 lines. |

## Outcome by round (objective)

| Round | Skill | conform repairs | wall-clock | tokens | tool calls | Go-dives | assertions |
|---|---|---|---|---|---|---|---|
| 1 | v0 | 1 | 7.3 min | 112.1K | 72 | 0 | 6/6 |
| 2 | v1 | **0** | 6.4 min | 107.5K | 71 | 0 | 6/6 |
| 3 | v2→v3 | **0** | 7.2 min | **99.9K** | 75 | 0 | 6/6 |

All three runs reached PROVEN with no credential leak. The v1 edits removed the
only repair loop (the action field-collision) and cut tokens; v2/v3 held the noise
floor while removing residual confusion (completeness chasing, fixture surprise,
needless re-records). Net skill growth: 334 → 378 lines (+44), all generic.
