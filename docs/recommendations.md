# agentprovider — Recommendations (generic, not AWX-specific)

Question driving this doc: **are the demo's recurring retries caused by AWX-specific gaps, or
by generic weaknesses in the agentprovider engine/skill?** Every finding below carries
provenance — a source `file:line` for engine claims, or the transcript metric + the analysis
that produced it for behavioural claims.

**Verdict:** The **engine is largely optimised for the generic case** — it already has
evidence-based field classification, observed-response suggestions, confidence grading, and a
`--force` escape hatch. Most of the retry tax is **skill/workflow orchestration**, not engine
deficiency. Three genuine *generic* engine improvements remain. None of the recommendations
are AWX-specific.

Provenance key:
- **[ENGINE]** `…/research-dynamic-provider/terraform-provider-dynamic` @ `f840970` (`git log -1`).
- **[SKILL]** `.claude/skills/agentprovider/references/cli-loop.md`.
- **[TRANSCRIPT]** subagent jsonl under `~/.claude/projects/-Users-simon-lynch-git-demo-awx-dynamic/<session>/subagents/workflows/wf_*/agent-*.jsonl`, metrics in `docs/recording-session-analysis.md`.

---

## What the engine already does generically (so do NOT "fix" these)

| Capability | Provenance | Why it's already generic |
|---|---|---|
| Evidence-based field classification (`FieldClass`: Optional / OptionalComputedDefaulted / Required / **IgnoreServerField** / Volatile / NeedsProbe) with High/Low confidence | [ENGINE] `cli/agentprovider/field_suggestions.go:34-79` | Classifies from *observed* responses, not from any API's vocabulary. |
| `record --suggest` emits `ignore_server_fields` + `field_suggestions` (`add_ignore_server_field`, `promote_to_optional_computed`, …) | [ENGINE] `cli/agentprovider/record.go:45,226-228`; [SKILL] `cli-loop.md:205-208` | The generic mechanism for "this field doesn't round-trip → ignore it." |
| `record --force` to overwrite an existing cassette | [ENGINE] `cli/agentprovider/record.go:95,145-147` | Re-record is a first-class operation; no need to hand-`rm`. |
| Introspect grades confidence (`source: options/sample`, `confidence: high/reduced`) and warns a single GET "cannot prove settable status" | [ENGINE] `cli/agentprovider/introspect.go:447-448,521` | Generic, framework-agnostic signalling. |
| Canonical loop already pairs `record --suggest` → `conform` | [SKILL] `cli-loop.md:126-127` | The right order is documented. |

---

## Generic ENGINE improvements (real gaps, API-agnostic)

### E1 — Default delete `expect_status` omits async `202` (and create omits poll patterns)

- **Finding:** bootstrap hardcodes `delete` → `expect_status: [200, 204]` and `create` →
  `[200, 201]`. Async APIs that return **`202 Accepted`** on delete fail immediately.
- **Provenance:** [ENGINE] `cli/agentprovider/bootstrap.go:585,587`; observed failure
  [TRANSCRIPT] `record` error `delete: expected status in [204], got 202` (takes 2 & 3 subagents).
- **Why generic:** `202 Accepted` for async create/delete is a standard REST idiom, not an AWX
  quirk. Any async API hits this.
- **Recommendation:** either (a) widen the default delete acceptance to the 2xx success class
  `{200, 202, 204}`, or (b) have `record --suggest` infer the accepted status from the *observed*
  response and emit a `set_expect_status` suggestion — consistent with the existing
  evidence-based model. Prefer (b): it generalises to create-poll and other status patterns.

### E2 — Introspect degrades silently to `sample/reduced`; no actionable cause

- **Finding:** Introspect fell back to `source: sample, confidence: reduced` **32×** vs
  `options/high` **33×** across one demo's subagents — ~50% degraded. The fallback is the likely
  trigger for the introspect re-call storm (take 1: **157** introspect calls, one agent **24×**).
- **Provenance:** [TRANSCRIPT] introspect-quality counts and the 157/24 figures in
  `docs/recording-session-analysis.md` (§Cause C, §S1), produced by grepping the subagent jsonl.
  Engine signalling exists at [ENGINE] `introspect.go:447-448,521`.
- **Why generic:** any API whose richer schema endpoint (OPTIONS/OpenAPI/`?describe`) is
  permission-gated will degrade; the agent re-introspecting fruitlessly is format-agnostic.
- **Recommendation:** when introspect degrades **because of auth/permission** (not absence of
  the endpoint), say so explicitly and emit a single actionable hint (e.g.
  `degraded: insufficient_token_scope`) so the caller fixes the credential **once** instead of
  re-calling. Pairs with W2 below.

### E3 — `record --suggest` cannot detect non-round-tripping declared-settable fields (LOAD-BEARING)

- **Finding:** This is the single most important finding and it **revises W1 downward.**
  `record --suggest` *is* correctly exposed and consumed — but `ignore_server_fields` came back
  **empty in 36/36** invocations, and the populated `field_suggestions` covered only
  response-only/nested fields (`related.*`, `launched_by.url`, `detail`) — **never** the boolean
  fields (`survey_enabled`, `ask_*_on_launch`, …) that actually fail conform. The mechanism does
  not surface the fields causing the retries.
- **Root cause:** introspect classifies a field `optional+default`/`optional+computed` from the
  schema descriptor (declared writable + declared default) with no observed-echo gate
  ([ENGINE] `cli/agentprovider/introspect.go:474-491`). `record --suggest` observes a *create*
  (plus possibly one GET); a create where the field equals the server default **cannot
  distinguish "round-trips" from "silently ignored."** The only place that distinction is drawn
  is conform's **mutation-check** (set to a non-default value, expect echo) — which runs *after*
  authoring, hence the repair→re-conform loop.
- **Provenance:** [TRANSCRIPT] direct count: `record --suggest` results = 36, non-empty
  `ignore_server_fields` = **0**, populated `field_suggestions` = 31 (all response/nested paths),
  from grepping the takes 30a7f432 + 3d1c4e56 subagent jsonl; failing-invariant histogram
  (`survey_enabled` 68, `ask_*_on_launch` ~68 each) in `docs/recording-session-analysis.md`
  §Cause A; classification logic at `cli/agentprovider/introspect.go:474-491`.
- **Why generic:** schema endpoints across frameworks (DRF, many OpenAPI generators) over-declare
  writable fields. Detecting non-round-trip requires a *write-then-readback probe*, which is
  framework-agnostic.
- **Recommendation:** give `record --suggest` (or a dedicated probe step, cf. the existing
  `FieldClassNeedsProbe`/`gather_probe_evidence` path in `field_suggestions.go`) a **write
  non-default → readback** capability so it can populate `ignore_server_fields` with
  silently-ignored declared-settable fields **before** the first conform. Today that detection
  lives only in conform's mutation-check, which is why the loop must fail once to learn it.
  **This — not W1 — is the fix for the dominant conform-retry class.**

---

## Generic SKILL / WORKFLOW improvements (orchestration, where most of the tax lives)

### W1 — Apply `record --suggest` output before conform (PARTIAL — does NOT fix the boolean class)

- **Finding (revised by E3):** Applying suggestions before conform is still good hygiene, but it
  is **not** the fix for the dominant conform-retry class. The measured evidence shows
  `ignore_server_fields` was **empty in 36/36** `record --suggest` results, so there was nothing
  to apply for the non-round-tripping booleans. W1 only helps the response/nested field
  suggestions that *were* populated (`field_suggestions` = 31/36). The boolean retries require
  the **engine** change in E3.
- **Provenance:** [TRANSCRIPT] 36/0/31 split (see E3); [SKILL] `cli-loop.md:126-127,205-208`.
- **Recommendation:** keep "apply emitted suggestions between record and conform" as a hygiene
  step, but **do not rely on it for the boolean/declared-settable retries** — those need E3.

### W2 — Mint the high-confidence (write-scoped) token once in the parent; share to subagents

- **Finding:** Each subagent independently obtains a token; ~50% degraded to read-token quality
  (E2). The parent already mints a token (`/tmp/wf-env.sh` referenced in the main session).
- **Provenance:** [TRANSCRIPT] introspect quality split (E2) + parent `source /tmp/wf-env.sh`
  calls visible in the main-session bash log (`docs/recording-session-analysis.md` session paths).
- **Recommendation:** mint/validate one high-confidence token in the orchestrator and pass it via
  the workflow env to every subagent, so none silently degrade. Generic to any auth-gated schema
  endpoint.

### W3 — Always re-record with `--force`; never hand-`rm` or hard-fail

- **Finding:** `record` failed with `cassette path already exists` — a re-record without
  `--force`. The flag exists; the agent didn't use it on the retry.
- **Provenance:** [ENGINE] `cli/agentprovider/record.go:145-147` (error text literally says "use
  --force to overwrite"); [TRANSCRIPT] verbatim `cassette path already exists` record error.
- **Recommendation:** skill rule — every record after the first uses `--force`. (Optional engine
  nicety: default to overwrite-with-warning, demoting this from error to noise.)

### W4 — Verify with `jq` / CLI output, not throwaway inline-python

- **Finding:** 12–23 tool errors per take inside subagents, dominated by inline
  `python3 - <<'PY'` heredocs failing on f-string quote-escaping / `KeyError` / `JSONDecodeError`.
- **Provenance:** [TRANSCRIPT] python error-type histogram (`JSONDecodeError` 6, `KeyError` 5,
  `TypeError` 1) and sample `SyntaxError` lines in `docs/recording-session-analysis.md` §S3/§2.
- **Recommendation:** steer verification to `jq` and the CLI's own machine output (`--format
  json`) / `.proven.json` sidecars. Generic; removes the largest self-inflicted error class at
  both main-thread and subagent levels.

### W5 — Cap introspect/record retries per subagent; fail fast to a repair pass

- **Finding:** The workflow's wall-clock is bounded by its slowest agent; outliers ranged to
  **9.3 min** (take 1, 24 introspects) and **7.3 min** (take 3) vs a ~1.5-min floor.
- **Provenance:** [TRANSCRIPT] per-agent duration spread in `docs/recording-session-analysis.md`
  §Aggregate subagent metrics / §S4.
- **Recommendation:** bound introspect/record attempts per agent (e.g. introspect once; ≤2
  record→suggest→repair cycles) and escalate to a dedicated repair rather than looping in-agent,
  so one unlucky contract can't stall the fan-out. Generic.

---

## Priority

| # | Recommendation | Class | Effort | Payoff |
|---|---|---|---|---|
| **E3** | **Write-then-readback probe so `--suggest` populates `ignore_server_fields` pre-conform** | **Engine** | **Med** | **Removes the dominant conform-retry class (booleans)** |
| W2 | Share one write-scoped token to subagents | Workflow | Low | Kills introspect degradation/storms |
| W4 | jq/CLI verification, not inline-python | Skill | Low | Removes largest error class |
| E1 | Default async `202` / infer status from observed | Engine | Med | Removes async-delete record failures |
| W3 | Always `--force` on re-record | Skill | Trivial | Removes a hard-fail retry |
| E2 | Loud, actionable introspect degradation | Engine | Low | Stops fruitless re-introspection |
| W1 | Apply `--suggest` output (hygiene only) | Skill | Low | Helps response/nested fields; NOT the booleans |
| W5 | Per-agent retry caps / fail-fast | Workflow | Med | Protects wall-clock from outliers |

**Bottom line (revised):** the engine's *plumbing* is generic and sound — suggestions are
correctly exposed and consumed. But the **detection** behind those suggestions has a real
generic gap: `record --suggest` cannot see non-round-tripping declared-settable fields (empty
`ignore_server_fields` 36/36), so the contract must fail conform once to learn them. **E3 is the
highest-leverage fix**, followed by the workflow/skill hygiene items (W2/W4/W3). No AWX-specific
special-casing is recommended or required. (This bottom line was revised after measuring the
`record --suggest` output directly — see E3.)
