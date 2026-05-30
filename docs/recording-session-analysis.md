# AWX Demo Recording — Session Analysis & Improvement Report

Analysis of the live Claude Code sessions that drive `demo/agentprovider-awx-v5.tape`,
covering the three full 16-contract takes recorded on 2026-05-30. Produced to surface
recurring inefficiencies and concrete fixes for future takes.

## Sessions analyzed

| Take | Session ID | Started | Duration | Path |
|---|---|---|---|---|
| 1 | `ba9f8925` | 15:23 | 20.0 min | `~/.claude/projects/-Users-simon-lynch-git-demo-awx-dynamic/ba9f8925-f43a-4dda-bbdb-b3ace10ca5f1.jsonl` |
| 2 | `30a7f432` | 15:54 | 19.9 min | `~/.claude/projects/-Users-simon-lynch-git-demo-awx-dynamic/30a7f432-05df-4b4c-aed9-d8a98be0d195.jsonl` |
| 3 | `3d1c4e56` | 16:38 | 17.9 min | `~/.claude/projects/-Users-simon-lynch-git-demo-awx-dynamic/3d1c4e56-bf55-488e-8fd1-a9eb9e7725bf.jsonl` |

Supporting artifacts:
- Contracts/cassettes: `/Users/simon.lynch/git/demo-awx-dynamic/.agentprovider/{contracts,cassettes}/`
- Agent-written learning: `~/.claude/projects/-Users-simon-lynch-git-demo-awx-dynamic/memory/job-template-needs-synced-project.md`
- Tape: `demo/agentprovider-awx-v5.tape` · Render script: `demo/record-awx.sh`
- **Subagent transcripts:** `~/.claude/projects/-Users-simon-lynch-git-demo-awx-dynamic/<session-id>/subagents/workflows/wf_<id>/agent-*.jsonl` (16 per take, plus `journal.jsonl` and `*.meta.json` per agent)

## Metrics

| Metric | Take 1 | Take 2 | Take 3 | Notes |
|---|---|---|---|---|
| Duration | 20.0 min | 19.9 min | 17.9 min | converging downward |
| Main-thread bash calls | 25 | 39 | 25 | take 2 was noisiest |
| Tool errors (non-zero exit) | 7 | 9 | 3 | mostly self-inflicted |
| `introspect` (main thread) | 2 | 4 | 3 | rest run inside the workflow |
| `terraform apply` invocations | 4 | 6 | 4 | phased + drift + retries |
| `curl` calls | 6 | 10 | 7 | manual AWX verification |
| inline `python3 -` heredocs | 10 | 23 | 16 | **primary error source** |
| `Workflow` tool calls | 1 | 1 | 1 | the 16-contract fan-out |
| Task/Agent subagents (main) | 0 | 0 | 0 | fan-out is via Workflow, not Task |

## Findings & improvement areas

### 1. Job launch fails on first apply — project not synced (HIGH)

In every take the `aap_job_launch` action returned `status=failed` on first attempt because
the job template's project had not finished its SCM sync. The agent recovered by destroying
(7 resources) and re-applying in **phases** (project + sync first, then full apply), costing
2–4 minutes and adding a destroy/re-apply cycle that muddies the recording.

- **Evidence:** `status=failed launch_type=manual` in takes 1 & 2; agent wrote
  `memory/job-template-needs-synced-project.md` capturing the root cause.
- **Fix:** bake the dependency into the demo. Either (a) pre-create a **synced** project
  fixture before the run and have the job template reference it, or (b) add an explicit
  `depends_on` + a project-sync wait in the generated Terraform graph, or (c) state the
  ordering in the prompt: "ensure the project SCM sync completes before launching the job."

### 2. Inline-python heredocs are the dominant failure source (HIGH)

10–23 ad-hoc `python3 - <<'PY'` blocks per take, with recurring **f-string quote-escaping
SyntaxErrors** and `TypeError: string indices must be integers`. These account for most of
the 3–9 tool errors per take and clutter the on-screen recording with stack traces.

- **Evidence (take 2):** `File "<string>", line 8 print(f"{r[\"kind\"]}...")` and
  `TypeError: string indices must be integers, not 'str'`.
- **Fix:** steer verification away from throwaway python. Prefer `jq` for JSON shaping,
  the `agentprovider` CLI's own machine output, or the proven `.proven.json` sidecars.
  A prompt nudge ("verify with jq or the CLI, not inline python") would cut the error rate
  and clean up the recording.

### 3. Subagent work is invisible on screen (MEDIUM — conflicts with demo goal)

The 16-contract build runs inside a single `Workflow` call, so each contract's
`introspect → bootstrap → record → conform → completeness` loop executes in workflow
sub-agents whose output never reaches the recorded terminal (it lives in separate agent
transcripts). The tape's stated intent — "leave its raw output on screen" — is undermined:
the viewer sees a workflow progress widget, not the CLI surface.

- **Fix:** decide the demo's story. Either (a) accept the workflow widget as the visual and
  lean into "16 in parallel," or (b) build 1–2 representative contracts **inline and visibly**
  first (showing the full CLI loop), then fan out the remaining 14 via the workflow.

### 4. Excessive manual AWX verification via curl (MEDIUM)

6–10 `curl` calls per take poke the AWX API directly to confirm resources/jobs. This overlaps
with what the proven data sources and `.proven.json` sidecars already assert, and adds noise.

- **Fix:** consolidate verification — one scripted summary at the end rather than per-resource
  curls, or rely on the data-source reads already in the Terraform graph.

### 5. Non-determinism across takes (MEDIUM)

Fixture IDs differ each run (org 125/126, jt 154, etc.), job pass/fail varies, and the
phased-apply path only triggers on failure. The recording is not reproducible take-to-take,
making it hard to script a known-good run.

- **Fix:** pin deterministic fixture names and pre-create the synced project so the happy path
  is the same every take, removing the destroy/re-apply branch from the recording.

### 6. Capture length still drives encode cost (LOW — partially addressed)

Takes capture ~12.5 min of frames; the gif palettegen path failed on this volume (now fixed
by switching the tape to direct mp4 output — see `demo/record-awx.sh`). Remaining lever:
`Set PlaybackSpeed 2` would halve the output duration and frame count for a tighter demo.

## Priority ranking

1. **Pre-sync the project** (removes the job-launch failure + destroy/re-apply detour) — #1, #5
2. **Reduce inline-python** (removes most tool errors + stack-trace clutter) — #2
3. **Decide subagent visibility story** (aligns recording with stated demo goal) — #3
4. Consolidate curl verification — #4
5. Consider `Set PlaybackSpeed 2` for a tighter cut — #6

## What is already working well

- **Correctness converged:** all 16 contracts reach `conform overall_passed=true` at 100%
  completeness with `.proven.json` sidecars every take.
- **Runtime proof holds:** `terraform apply` + no-drift second apply pass; real AWX job +
  workflow job launch successfully (after the project-sync fix is applied in-run).
- **Timing is stable and improving:** 20 → 17.9 min, comfortably inside the 25 min tape window.
- **Fresh-build discipline:** no git-history reuse observed (0 `git show`/`git log` for
  contract recovery); the tape's `rm -rf` cleanup yields a genuine from-scratch build.

---

# Subagent (workflow) analysis

The 16-contract build runs as **16 parallel workflow subagents** spawned by a single
`Workflow` tool call in the main session. Each subagent owns one contract and runs the full
`introspect → bootstrap → record → conform → completeness → emit-proof` loop in its own
transcript. These are the real workhorses — the main session only orchestrates and assembles.

## Aggregate subagent metrics

| Metric (sum across 16 subagents) | Take 1 | Take 2 | Take 3 |
|---|---|---|---|
| Total bash calls | 331 | 257 | **400** |
| Total tool errors | 15 | 12 | **23** |
| `introspect` calls | **157** | 20 | 20 |
| `bootstrap` calls | 16 | 17 | 17 |
| `record` calls | **3** | 23 | 34 |
| `conform` calls | **8** | 43 | 50 |
| `completeness` calls | 30 | 32 | 37 |
| Avg agent duration | 2.8 min | **2.1 min** | 3.3 min |
| Slowest agent | **9.3 min** | 3.6 min | 7.3 min |
| Fastest agent | 1.6 min | 1.2 min | 1.5 min |

## Findings

### S1. Introspect over-calling is intermittent but catastrophic (HIGH)

Take 1's subagents ran `introspect` **157 times** (≈10× per agent; one agent ran it **24
times** over 9.3 min) while completing only **3 records and 8 conforms** — the introspect loop
ran away and starved the rest of the pipeline. Takes 2 and 3 were healthy (20 introspects ≈ 1
per agent). So the behaviour is **bimodal**: when an agent fails to lift the introspect output
on the first call, it re-introspects repeatedly instead of caching it.

- **Fix:** enforce "introspect once, lift the field map, never re-introspect" in the subagent
  prompt/skill. This is the single biggest variance reducer — it turned take 1's slowest agent
  into a 9.3-min outlier that bounded the whole run's wall-clock.

### S2. Record/conform retry churn is the dominant steady-state cost (HIGH)

In the healthy takes the cost shifts from introspect to **re-recording**: take 3 ran 34
records + 50 conforms (vs take 2's 23 + 43) — agents re-record the cassette and re-run conform
2–6× until invariants pass. Take 3's churn drove bash calls to 400 and avg duration to 3.3 min.
This matches the known learning that "re-records are the dominant cost."

- **Fix:** reduce re-record cycles — get the contract right before first record (lift settable
  fields from introspect, apply standard invariants up front). Fewer record→conform→repair
  loops directly shrinks the slowest-agent wall-clock.

### S3. Same inline-python fragility inside subagents (MEDIUM)

Subagents inherit the main thread's habit: 12–23 tool errors per take, dominated by
`Exit code 1/2` from throwaway python verification scripts (quote-escaping / type errors).
Each error costs a retry inside an agent that the workflow is waiting on.

- **Fix:** same as main-thread #2 — steer subagent verification to `jq`/CLI output, not
  inline python heredocs.

### S4. Slowest-agent bounds wall-clock; high per-agent variance (MEDIUM)

The workflow completes only when its slowest agent finishes, so outliers dominate: agents
ranged **1.2 → 9.3 min** and bash calls **11 → 61** for structurally identical work. Take 1's
single 9.3-min agent (24 introspects) likely set that take's whole 20-min duration.

- **Fix:** cap introspect/record retries per agent and fail fast to a repair pass, so one
  unlucky agent can't stall the fan-out. Reducing S1/S2 variance tightens the whole run.

## Root causes of the retries (verbatim from subagent tool results)

The retries are not random — three concrete causes, all reproducible:

### Cause A — Non-round-tripping AWX boolean/choice fields drive conform failures

The conform invariant failures are dominated by AWX boolean/choice fields the contract
asserts but AWX does not echo back settably. Failure counts across takes 2+3:

| Field (failed invariant) | count |
|---|---|
| `prevent_instance_group_fallback` | 79 |
| `allow_simultaneous` | 75 |
| `ask_inventory_on_launch` | 68 |
| `ask_labels_on_launch` / `ask_limit_on_launch` / `ask_tags_on_launch` / `ask_scm_branch_on_launch` / `ask_skip_tags_on_launch` | 68 each |
| `survey_enabled` | 68 |
| `ask_variables_on_launch` | 64 |
| `allow_override` | 44 |
| `scm_clean` / `scm_delete_on_update` / `scm_track_submodules` / `scm_update_on_launch` | 38 each |

These are server-side booleans that default `false` / are non-pinnable. Bootstrap/introspect
pulls them into the contract's settable surface; the field then fails its round-trip invariant,
the agent repairs (routes to `ignore_server_fields` or marks computed) and **re-conforms**.
`overall_passed` was `true` 157× vs `false` 11× — most contracts pass, but the boolean fields
force a repair→re-conform cycle on the job-template / workflow-template / project / credential
contracts especially.

- **Fix:** pre-classify these known AWX booleans as computed/ignored in the seed (or teach the
  skill to exclude `ask_*_on_launch`, `scm_*`, `survey_enabled`, `allow_*` from the settable
  surface by default for AWX). Eliminates the largest single retry driver.

### Cause B — Delete/record status mismatches and stale cassettes drive record failures

Verbatim `record` errors:

- `delete: expected status in [204], got 202` — AWX deletes are **async (202 Accepted)**, not 204.
- `delete: expected status in [204], got 409 (body=…active_job…)` — can't delete a resource
  with a **running job** (the launch action left one active).
- `create: expected status in [201], got 400 (body=…inputs:RED…)` — **credential** `inputs`
  payload shape rejected.
- `cassette path already exists` — re-record without clearing the prior cassette → hard error.
- `usage: agentprovider record …` (exit 2) — malformed record invocation (wrong args).

- **Fix:** (1) set the AWX delete expectation to accept `202` (and gate deletes on no-active-job);
  (2) have re-records clear/overwrite the cassette (`--force` or `rm` first) instead of erroring;
  (3) fix the credential `inputs` shape in the seed; (4) the exit-2 usage errors are
  malformed-command retries — same inline-fragility class as the python errors.

### Cause C — Introspect degraded to read-token quality ~half the time

Across the subagents, introspect returned `source: options, confidence: high` **33×** but
`source: sample, confidence: reduced` **32×** — i.e. **~50% of introspect calls fell back to
read-token quality**. A reduced result gives a weaker field map, which is the likely trigger
for take 1's introspect re-call storm (agents re-introspecting to chase `options/high`).

- **Fix:** ensure every subagent inherits the **write-scoped** token (mint once in the parent,
  pass `AWX_TOKEN` into the workflow env) so no agent silently degrades to sample/reduced.
  This is the documented "introspect needs write token" issue showing up per-subagent.

## Subagent priority ranking

1. **Introspect-once enforcement** (kills the 157-call runaway + the 9.3-min outlier) — S1
2. **Cut record/conform retries** (the steady-state cost in healthy takes) — S2
3. **De-python subagent verification** (fewer in-agent retries) — S3
4. **Per-agent retry caps / fail-fast** (protect wall-clock from outliers) — S4

## Cross-cutting takeaway

The main-session and subagent findings rhyme: **inline-python errors** and **retry churn**
(introspect in the bad case, record/conform in the good case) are the two recurring tax lines
at both levels. Fixing introspect-once + reducing re-records + replacing inline-python with
jq/CLI would compress every take and — more importantly — collapse the take-to-take variance
(20 vs 17.9 min, 12 vs 23 errors) that currently makes the recording unpredictable.
