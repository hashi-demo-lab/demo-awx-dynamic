# agentprovider — improvement log (CLI + skill)

Running, batched log of potential improvements surfaced while running the AWX live
eval. Goal: collect **all** suggestions in one place so they can be actioned in a
single pass rather than dribbled out round-by-round. Each item: what, evidence,
proposed fix, where it lands (CLI engine vs skill doc).

Status legend: 🔴 open · 🟡 partial · 🟢 done

---

## A. CLI / engine — bootstrap scaffold defaults (highest leverage)

These are the dominant cost: every sub-run hand-fixes the same scaffold guesses, and
when one is missed it fails only at `record`, forcing a re-record. Fixing them in the
scaffold removes the friction at the source.

- 🔴 **A1 — `connection.base_url` placeholder.** Bootstrap emits `${env.<TYPE>_BASE_URL}`
  (e.g. `${env.AAP_JOB_BASE_URL}`). Every run rewrites it to the real origin env var.
  *Fix:* default to a single `${env.BASE_URL}` or prompt/derive from the seed URL's origin.
  *Evidence:* it-14 (all 7), it-15, it-16 baseline/R1.
- 🔴 **A2 — auth scaffold is invalid / wrong env-var names.** Bootstrap emits a bearer
  block as `auth.type: bearer` + `token:`, which the engine rejects (only `auth.type:
  header` with `header:`/`value:` is accepted); for basic it guesses `${env.X_USER}`
  when the env exports `X_USERNAME`. Fails at `validate`/`record`.
  *Fix:* emit a valid auth skeleton (correct `type`/keys) and leave env-var names as
  obvious `${env.USERNAME}`/`${env.PASSWORD}` tokens, or omit auth with a TODO comment
  rather than an invalid block. *Evidence:* it-16 R1 host (bearer), it-15 host (AWX_USER).
- 🔴 **A3 — op paths scaffolded as `/` or `{param}`.** Bootstrap leaves `/` or
  OpenAPI-style `{id}` paths; every run rewrites to `/api/v2/.../${id}/`.
  *Fix:* when seeding from a live URL/introspect, carry the real path; emit `${...}`
  not `{...}`. *Evidence:* it-14/15/16 host + job_template.
- 🔴 **A4 — identity picks the wrong id field.** Bootstrap chose `instance_id` (a UUID)
  over `id` (integer PK used in URLs) for hosts. *Fix:* prefer the field that the
  read/update path interpolates / the integer PK. *Evidence:* it-15 host, it-16 host.
- 🔴 **A5 — `expect_status` defaults.** Scaffold defaults don't match live (create `201`,
  async DELETE/PUT `202`). *Fix:* when recording is available, set from observed status;
  otherwise emit the conventional `201`/`204` and flag. *Evidence:* it-14 inventory (202),
  it-16 (create 201).
- 🔴 **A6 — `bootstrap --kind action` requires a seed source.** `--type X --action launch`
  alone errors with an unhelpful usage message. *Fix:* allow a bare action scaffold, or
  emit a hint naming which seed flag is needed. *Evidence:* it-14 workflow_job_launch.

## B. CLI / engine — behavior

- 🔴 **B1 — server-derived input detection.** When a create echoes a *different* value
  than submitted for a field (server derives/ignores it — e.g. AWX sets `organization`
  from the project), the contract must mark it `computed` + drop from body. Today this is
  only discovered via a failed `create_echoes_inputs` → re-record loop (cost: 3 re-records
  / ~200s on job_template, every run). *Fix:* `conform`/`record` could detect "sent X, got
  Y, field absent from your body intent" and emit a repair-hint suggesting `computed`,
  saving the blind re-record. *Evidence:* it-15, it-16 baseline + R1 (the single biggest
  repeat cost in the whole eval).
- 🔴 **B3 — introspect FK/derived classification.** introspect returns FK and
  server-derived fields as low-confidence `review_descriptor_metadata` rows the agent
  must hand-resolve one at a time (per-field cost). The rest of the pipeline is already
  multi-field (one OPTIONS → all fields → one `--from-introspect` lift → one record →
  one conform). *Fix:* classify FK ids (settable vs derived-from-another-FK vs read-only)
  in introspect so they land in the batched lift instead of per-field review. This is the
  main remaining "per-field" step in introspect→contract. *Evidence:* every resource run.
- 🟡 **B2 — `field:` dotted projection** now works (was a limitation). Keep; no action.

## C. Skill (SKILL.md / references)

- 🟢 **C1 — front-load a one-pass scaffold-fixup checklist** before `record` (base_url,
  auth, paths, identity, expect_status). *Done it-16 R1.* Measured impact: neutral on
  tokens/time because the dominant cost (B1 re-records) is a record-time discovery the
  checklist can't pre-empt. Keep it (correctness/clarity win) but it is not a speed lever.
- 🟢 **C2 — server-derived-FK default stance** added at the bootstrap step (it-16 R2). Measured impact: job_template re-records 3→2; NOT eliminated — the agent still pins a passed-in FK value and learns the override at record. Confirms B1 (CLI detection) is the real fix.
- ⚪ **C2-old (superseded).** The "create echoes a
  different value → mark computed" rule is in the skill but agents still pin the submitted
  value and re-record. *Fix:* state it at the bootstrap step as a default stance ("for any
  FK the server might derive from another FK — org-from-project, tenant-from-parent —
  default to `computed` until a record proves it is independently settable"), not just as
  a failure-recovery note.
- 🟢 **C3 — de-duplicated** the §2 fixup checklist (it had duplicated "Get these right up front"); collapsed to a pointer. Net skill size 549→559 lines (the C2 stance is the only real add). Trimming further has low ceiling — token weight is not the bottleneck; re-records are.

## D. Eval harness (awx-live.json) — DONE, logged for completeness

- 🟢 **D1 — verified `cleanup_complete`** assertion + RUN_TAG + teardown manifest. (committed)
- 🟢 **D2 — distinct fixture vs record namespaces** (`-fixture-*` vs `-<contract>-*`) so a
  concurrent sub-run can't delete a shared fixture as stale. (committed)

---

## Efficiency-round measurements (lean 2-contract benchmark, new CLI 25be474)

| Round | Skill change | host tok/s | job_template tok/s (re-records) | total tok | wall s |
|---|---|---|---|---|---|
| baseline | current skill | 33,779 / 114.9 | 62,513 / 349.3 (3) | 96,292 | 349.3 |
| R1 | front-load fixup checklist (C1) | 41,654 / 121.3 | 56,841 / 348.3 (3) | 98,495 | 348.3 |
| R2 | server-derived-FK stance (C2) + de-dup (C3) | 36,841 / 112.7 | 65,814 / 310.9 (2) | 102,655 | 310.9 |

**Conclusion after 3 measured rounds:** skill-side optimization is exhausted for
token/speed. Totals are flat-to-worse (96k→98k→103k tokens; wall 349→348→311s), and
job_template's re-records only edged 3→3→2. The dominant cost is **record-time discovery
of AWX-specific behavior** (server-derived `organization`) plus the **scaffold papercuts**
(identity/base_url/auth) — neither is removable by skill prose; the agent still hand-fixes
or learns-at-record. The real, batchable wins are all CLI-side: **A1–A6** (correct scaffold
defaults) and **B1/B3** (detect server-derived inputs + classify FKs in introspect). Those
turn the per-field, re-record-prone steps into the same one-pass flow the rest of the
pipeline already has. Recommend actioning A+B as a single engine PR in research-dynamic-provider.
