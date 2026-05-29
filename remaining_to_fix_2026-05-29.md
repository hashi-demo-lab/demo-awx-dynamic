# agentprovider CLI/engine — remaining to fix (2026-05-29)

Open **`cli_engine`** punch-list, verified at the **source level** against
`~/git/research-dynamic-provider/terraform-provider-dynamic` @ `main` HEAD
(`98066f8`) — the code in the shipped binary `~/.local/bin/agentprovider` (13:39).
Full narrative + per-round detail:
[`agentprovider-cli-vs-skill-issues.md`](agentprovider-cli-vs-skill-issues.md).

Already shipped this round (do **not** re-open): CLI-A numeric `default:`
(`0f00180`/`0bebb75`), CF-1 (`240c637`), CF-2 (`8f85acd`), CF-3 hint (`829fad4`),
CF-4 (`061aed1`), CF-6 (`d182fbb`).

Severity: `high` (causes a failure / repair loop or rewards a bad contract) ·
`med` (costs a dead-end) · `low` (cosmetic / message precision).

---

## 1. R1-1 — `record` false-positive "will fail conform on re-record" warning · **high**

- **Symptom:** fires on **every** CRUD resource for any field deliberately changed
  in `update_to` (round 6: `description`, `max_hosts`, `variables`, `forks`,
  `enabled`, …). Text: *"conformance.example pins X but the live run observed
  X-updated — this contract will fail conform on re-record. Move X out of
  conformance.example into conformance.expect."*
- **Reality:** **conform passes anyway.** `record` compares `example` against the
  **last (post-update)** observed value; `conform` checks `example` against the
  **create-time** response and `update_to` against the updated one — so
  `example != update_to` is correct by design and a re-record reproduces a matching
  cassette.
- **Why it's harmful, not just noisy:** the suggested fix (move the field to
  `conformance.expect.<f>: {not_null: true}`) **drops the create-time value check in
  `create_echoes_inputs`** — it actively weakens the proof.
- **Source:** `cli/agentprovider/record.go:445` (warning string); the surrounding
  loop sets `state = updated` (≈ line 530) before the comparison → compares to the
  post-update value. No fix commit exists.
- **Fix:** compare `example` against the **create-phase** observation (or suppress
  the warning when the field also appears in `update_to`).
- **Status:** running 6 rounds. Highest-noise, highest-value.

## 2. R3-Q — completeness / `--emit-proof` rewards thin (green-washed) contracts · **high**

- **Symptom:** the 100% gate counts a **modeled** field and an **ignored** field
  identically, so parking an API-**settable** input in `ignore_server_fields` scores
  the same as exposing it. Round 6 `job_template` reached 100% while hiding 3
  settable knobs (`execution_environment`, `webhook_credential`,
  `prevent_instance_group_fallback`) in `ignore_server_fields`.
- **Source:** **zero** occurrences of `settable` in the Go source; `completeness`
  has no settable-vs-`ignore_server_fields` cross-check. `completeness` *does*
  already accept request-schema evidence (`--openapi`, `--metadata <OPTIONS json>`)
  — the cross-check just isn't wired to it.
- **Fix:** when a field present in the **request schema** (OpenAPI request body /
  `OPTIONS` POST) appears in `ignore_server_fields`, warn (or score separately):
  *"ignored N settable inputs."* Makes the gate measure quality, not just coverage.
- **Priority raised — this is about REPRODUCIBLE quality, not just thin contracts.**
  Rounds 7 and 8 ran *identical* skill green-wash guidance yet `job_template` swung
  **opt-cov 1.0 / 0 dumped → 0.48 / 22 dumped** (the agent dumped the 16
  `ask_*_on_launch` toggles one run, modeled them the next). Prose guidance **cannot
  deterministically** prevent green-washing on a verbose object; only this mechanical
  gate can. Without it, contract quality is sample-dependent.

## 3. R4-2 — action `type` ending in `_<verb>` silently double-suffixes · **med**

- **Symptom:** `type: awx_job_launch` + verb `launch` registers as
  `dynamic_awx_job_launch_launch`; the first `plan` fails *"no action schema for
  dynamic_awx_job_launch"* **after** a record has already been paid for.
- **Source:** no `_launch_launch` / type-ends-in-verb detection anywhere; `validate`
  on such a contract returns `valid: true` with no diagnostic.
- **Fix:** warn at contract load / `validate` / `preflight` when `type` ends in
  `_<declared-verb>`.

## 4. R9-1 — `optional_default_consistency` misses sent-null-then-canonicalized · **med**

- **Symptom:** a modeled-`optional` string field sent as `null` in the create body
  that the server canonicalizes to `""` (or another non-null) passes the **offline**
  `optional_default_consistency` gate, then fails at `terraform apply` with *"Provider
  produced inconsistent result after apply: &lt;field&gt; was null, server returned
  \"\""*. Observed on `job_template.webhook_service` (AWX `OPTIONS` reports
  `default: None`, but live create returns `""`).
- **Root cause:** the gate only fires on fields **omitted** from the recorded create
  body (omitted → server-defaulted). A field **present-as-null** in the body is
  treated as "supplied", so a `null → non-null` server canonicalization is never
  flagged offline and only surfaces at live apply (cost: a repair + re-record).
- **Fix:** also flag *null-in-create-body → non-null-in-response* (a
  canonicalization), not just *omitted → defaulted* — i.e. recommend `optional+computed`
  for it. Pairs with the existing `promote_to_optional_computed` hint.

## 5. CF-3 (residual) — `bootstrap` omits `allow_insecure` / `allow_private_host` · **low**

- The record/preflight *hint* is fixed, but `bootstrap` still does not **emit** these
  flags for an `http://` / RFC-1918 `base_url`, so the author sets them by hand.
- **Fix (optional):** infer them at bootstrap from the target URL scheme/host.
