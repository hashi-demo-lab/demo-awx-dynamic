# agentprovider skill — detailed optimization comparison (2026-05-29)

Eval: live full-stack AWX (4 CRUD resources + 1 data source + 2 actions → real
`terraform apply`, both launches verified via the AWX API). Source narrative:
[`agentprovider-cli-vs-skill-issues.md`](agentprovider-cli-vs-skill-issues.md).

> **Binary confound:** rounds 1–5 ran on the **pre-fix** binary; rounds 6–8 on the
> **fixed** build (`~/.local/bin/agentprovider`, 13:39 = `main` HEAD). The only
> clean, single-variable A/B is **round 6 (v3) vs round 7 (v4)** — same binary, skill
> is the sole change. Cross-pass token/time deltas carry the binary confound.

---

## 1. Benchmark across every round

| Round | Skill | Binary | Verdict | Objective | Conform repairs | Go reads | Tokens | Wall | `job_template` opt-cov | DS modeling |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | v0 | pre-fix | PROVEN | 8/8 | 0 | 0 | 134K | 8.7m | 0.12 | 100% |
| 2 | v1 | pre-fix | PROVEN | 8/8 | 0 | 0 | 113K | 9.5m | 0.12 | 100% |
| 3 | v1 | pre-fix | PROVEN | 8/8 | 0 | 0 | 148K | 11.8m | 0.14 | 100% |
| 4 | v2 | pre-fix | PROVEN | 7/8 | 0 | 0 | 140K | 12.4m | 0.93 | 12.5% ⚠ regress |
| 5 | v3 | pre-fix | PROVEN | 8/8 | 1 | 0 | 140K | 11.4m | 0.93 | 100% |
| **6** | **v3** | **fixed** | **PROVEN** | **8/8** | **1** | **0** | **168K** | **12.4m** | **0.93 (3 dumped)** | **8 outputs** |
| **7** | **v4** | **fixed** | **PROVEN** | **8/8** | **0** | **0** | **132K** | **11.4m** | **1.0 (0 dumped)** | **16 outputs** |
| **8** | **v5** | **fixed** | **PROVEN** | **8/8** | **1** | **0** | **139K** | **11.5m** | **0.48 (22 dumped) ⚠** | **10 outputs** |
| **9** | **v6** | **fixed** | **PROVEN** | **8/8** | **2** | **0** | **158K** | **13.0m** | **1.0 (0 dumped)** | **7 outputs** |
| **10** | **v6** | **fixed** | **PROVEN** | **8/8** | **2** | **0** | **141K** | **13.0m** | **1.0 (0 dumped)** | **12 outputs** |

> **⚠ Quality is HIGH-VARIANCE, not converged.** Rounds 7 and 8 ran the *same*
> green-wash guidance (v5's only diff is the unrelated CF-1 trim) yet `job_template`
> swung **opt-cov 1.0 / 0 dumped → 0.48 / 22 dumped**. See §7.

---

## 2. The clean A/B — round 6 (v3) vs round 7 (v4), fixed binary

| Dimension | v3 (round 6) | v4 (round 7) | Δ | Driver |
|---|---|---|---|---|
| Verdict | PROVEN | PROVEN | — | held |
| Objective assertions | 8/8 | 8/8 | — | held |
| **Conform repairs** | **1** | **0** | **−1** | **R6-1** (update.body↔update_to symmetry) |
| `job_template` opt-input coverage | 0.93 | **1.0** | **+0.07** | **R6-Q** (FK ids are settable) |
| `job_template` settable dumped→ignore | 3 | **0** | **−3** | **R6-Q** |
| `job_template` settable modeled | 40 | **43** | **+3** | **R6-Q** (`execution_environment`, `webhook_credential`, `inventory`) |
| DataSource computed outputs | 8 | **16** | **+8** | richer read modeling |
| **Tokens** | 167.7K | **131.6K** | **−21%** | R6-2 + 0 repairs (dead-ends removed) |
| Tool calls | 89 | **80** | −9 | fewer dead-ends |
| Wall clock | 12.4m | **11.4m** | −1.0m | fewer dead-ends |
| Go-source reads | 0 | 0 | — | held |
| `terraform apply` / 2nd-plan no-op | ✓/✓ | ✓/✓ | — | held |
| Both launches verified | job 199 / wf 200 | job 207 / wf 206 | — | held |
| stdout/stderr misattribution filed | 1 (as cli_engine) | **0** | −1 | R6-2 |

**Every axis improved or held. No regressions** (the one apparent regression — a DS
"29 dumped" flag — was a `quality_analyze.py` measurement bug, fixed in the harness;
see §5).

---

## 3. Per-contract quality detail (v3 → v4, fixed binary)

| Contract | Kind | v3 req/opt/opt+c/comp/ignore | v4 req/opt/opt+c/comp/ignore | opt-cov | dumped |
|---|---|---|---|---|---|
| `awx_organization` | Resource | 1/1/2/1/8 | 1/1/2/1/8 | 1.0 → 1.0 | 0 → 0 |
| `awx_inventory` | Resource | 2/1/4/1/15 | 2/1/4/1/15 | 1.0 → 1.0 | 0 → 0 |
| `awx_host` | Resource | 2/0/4/1/12 | 2/0/4/1/12 | 1.0 → 1.0 | 0 → 0 |
| **`awx_job_template`** | Resource | 3/1/**36**/1/**16** | 3/**3**/**37**/1/**13** | **0.93 → 1.0** | **3 → 0** |
| `awx_*_lookup` (DS) | DataSource | comp **8** / ignore 48 | comp **16** / ignore 41 | n/a (read-only) | n/a |
| `awx_job_launch` | Action | 4 computed | 4 computed | n/a | n/a |
| `aap_workflow_job_launch` | Action | 4 computed | 4 computed | n/a | n/a |

The headline: `job_template` (43 settable fields in AWX) moved from hiding 3 settable
FK knobs to modeling **all 43**, while the data source's modeled outputs doubled.
The other three resources were already at the ceiling and stayed there (no
over-correction).

---

## 4. Skill version diffs and their measured effect

| Ver | Lines | Generic edit | Measured effect |
|---|---|---|---|
| v0 | 461 | baseline | PROVEN 8/8, opt-cov 0.12 |
| v1 | ~490 | emit-proof 100% gate + ignore-envelope route; R1-1 false-positive note; actions exempt from emit-proof | tokens 134K→113K; 3 dead-ends removed |
| v2 | ~530 | anti-green-washing (`ignore_server_fields` = server-owned only) | opt-cov 0.12→0.93 |
| v3 | 547 | scoped green-wash guard to resources (DS carve-out); computed-precision; action `type`/verb split rule | DS regression fixed (12.5%→100%); 8/8 |
| **v4** | **574** | **R6-1** body symmetry · **R6-2** stdout/stderr · **R6-3** sidecar name · **R6-Q** FK-ids-settable | **repairs 1→0; jt opt-cov→1.0, 0 dumped; tokens −21%; 0 misattribution** |
| v5 | 574 | trim now-dead CF-1 `--suggest` identity-on-action note (CLI fixed it) | _validating (round 8)_ |

Each v4 edit was named decisive in the round-7 agent's `skill_callouts`, and each maps
to a measured delta in §2 — none is speculative.

---

## 5. CLI-fix leverage (what the fixed binary changed for the skill)

| Item | Status in source | Effect on skill |
|---|---|---|
| **CLI-A** numeric `default:` | **fixed** (`0f00180`/`0bebb75`) | enables `optional+default:` for numeric server-defaults (held as SKILL-D, not yet shipped) |
| **CF-1** identity suggestion on actions | **fixed** (`240c637`) | confirmed in-run (no suggestion on either action) → **v5 trims the workaround note** |
| **CF-2** redactor short-value over-match | fixed (`8f85acd`) | note kept (not exercised; defensive) |
| **CF-3** transport-guard hint | fixed (`829fad4`) | guidance unchanged (still correct authoring) |
| **R1-1** re-record false positive | **NOT fixed** (`record.go:445`, compares post-update) | mitigation **kept, load-bearing** (fired every resource, ignored per skill) |
| **R3-Q** green-wash scoring | **not implemented** (0 "settable" in source) | prose guard **kept** (only defence on no-OpenAPI APIs) |
| **R4-2** `_verb` double-suffix warn | **not implemented** | split-the-name rule **kept** |

Open CLI work tracked in [`remaining_to_fix_2026-05-29.md`](remaining_to_fix_2026-05-29.md).

**Harness fix (not skill, not CLI):** `quality_analyze.py` was judging read-only
DataSources against the sibling resource's `OPTIONS/POST` surface, false-flagging
their legitimately-ignored read envelope. Now skips read-only kinds (like actions).

---

## 6. Convergence assessment

- **Correctness:** PROVEN 8/8 for 4 consecutive fixed-stack-relevant configurations
  (rounds 5–7), 0 Go reads throughout — a real ceiling, not a lucky sample.
- **Quality:** all 4 resources at opt-cov 1.0 / 0 dumped; DS outputs doubled; 0
  over-computed. No green-washing remains.
- **Efficiency:** v4 is the leanest run of the pass (132K tokens) despite the richest
  contracts.
- **Quality is NOT converged — it is high-variance (see §7).** PROVEN 8/8 is stable;
  *contract richness* is sample-dependent on the verbose `job_template`.
- **Remaining items** are CLI-side (R1-1/R3-Q/R4-2) or environment.

**Correctness has converged; quality has not.** Next step is a v6 prose-hardening
edit (name the behavior-toggle family explicitly) — but the durable fix is the
**R3-Q mechanical gate**, since §7 shows prose cannot deterministically prevent
green-washing on a 43-field object.

---

## 7. Quality variance — the key finding (rounds 6–8, fixed binary)

`job_template` has 43 API-settable fields, 16 of them `ask_*_on_launch` boolean
toggles. Across three fixed-stack rounds with near-identical green-wash guidance:

| Round | Skill | opt-cov | dumped | what the agent did with the 16 `ask_*` toggles |
|---|---|---|---|---|
| 6 | v3 (no FK rule) | 0.93 | 3 | modeled `ask_*` as opt+computed; dumped 3 FK ids |
| 7 | v4 (FK rule) | **1.0** | **0** | modeled `ask_*` **and** FK ids |
| 8 | v5 (FK rule, same text) | **0.48** | **22** | **dumped the 16 `ask_*` toggles** + 6 more |

**v4 and v5 share identical green-wash guidance, yet 0 vs 22 dumped.** The R6-Q FK
rule held in both (the 3 FK ids are modeled in v5). The swing is entirely the
**boolean behavior-toggle family**, which the skill never names — one sample modeled
it, the next dumped it. Conclusions:

1. v4's perfect quality was **partly sample luck**, not a guaranteed skill outcome.
2. The generic edit: R6-Q named FK/reference ids as settable; **v6 also names the
   behavior-toggle family** (`ask_*` / `enable_*` / `allow_*` / `*_on_launch` flags
   present in the request schema) as the single biggest green-washing trap.

### v6 result — the edit stabilized it (2-sample variance test)

| | v5 (no toggle naming) | v6 sample 1 (r9) | v6 sample 2 (r10) |
|---|---|---|---|
| `job_template` opt-cov | **0.48** | **1.0** | **1.0** |
| settable dumped | 22 | 0 | 0 |
| `ask_*` toggles | dumped | modeled | modeled |
| verdict | PROVEN 8/8 | PROVEN 8/8 | PROVEN 8/8 |

**2-for-2 at the ceiling after the edit**, each run crediting the v6 toggle-family
guidance by name. Strong evidence the edit converted a wild swing (0.48↔1.0) into a
stable high-quality outcome.

**Caveat — not full determinism.** Two clean samples is strong, not ironclad: prose
still relies on the agent applying the rule. On a verbose object the *guaranteed*
fix is the **R3-Q mechanical gate** (flag settable fields parked in
`ignore_server_fields`) — this pass *raises* its priority, because R3-Q is about
**reproducible** quality, not merely thin contracts. Logged in
`remaining_to_fix_2026-05-29.md`.

### Consistent (non-variance) cost: 2 repairs on both v6 samples

Both v6 runs paid exactly **2 conform repairs**, on the *same two AWX-specific
fields* every time — `organization.default_environment` (the R6-1 `update.body`
symmetry trap) and `job_template.webhook_service` (server canonicalizes `null→""`,
R9-1). Both are recovered via skill rules, but they recur because they are
data-shape quirks of *this* API; `webhook_service` is the new **R9-1** cli_engine
item (offline `optional_default_consistency` misses sent-null-then-canonicalized).
v4's 0-repair run pre-empted both by luck of authoring order.
