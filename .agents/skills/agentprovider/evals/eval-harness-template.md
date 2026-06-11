# Eval-harness prompt template (lean AWX runs)

Boilerplate that belongs in every spawned eval agent's prompt — these are
HARNESS conventions learned across the d1–d10 + m3val campaigns, not skill
content:

1. Worktrees spawn at main's tip: FIRST `git reset --hard <eval branch>` in
   the worktree root and verify the expected HEAD before building.
2. Build the CLI fresh from the worktree; ONE freshness probe against a flag
   that exists only at the eval HEAD (note: Go help prints single-dash flags,
   so `grep -- -flagname`). Then verify `which agentprovider` resolves to the
   WORKDIR bin after sourcing setup.sh — a stale ~/.local/bin binary silently
   shadowing PATH invalidates every fix-validation verdict (it happened).
3. Per the skill's step 0: write setup.sh ONCE; every later command starts
   `source setup.sh && …`. Eval reports count preamble_repetitions (target 0).
4. Credentials: source the env from ITS OWN directory (relative-path cat
   inside .env files silently yields empty values otherwise); never print
   values; mint a write-scoped token; revoke it in cleanup and verify 401.
5. RUN_TAG-namespace every created object; pre-clean ONLY your tag (parallel
   evals exist); teardown verifies zero leftovers FOR DELETABLE TYPES (note:
   delete-less types like AWX labels are removed via parent cascade or are
   API-GC'd — scope the zero-leftover assertion accordingly).
6. Save artifacts as you go to the ABSOLUTE workspace path outside the
   worktree; the final MESSAGE is the report (report.md writes may be
   blocked by the harness).
7. Do not read prior iterations' workspace outputs (cross-eval contamination).
8. Generated repos are build-free: run `go mod tidy` once before
   `go test ./internal/provider -run TestGeneratedReplay`, and check the
   test's actual output — a piped exit code can mask a FAIL.
9. Report objective counts (cmd_invocations with ordered list,
   record/conform iterations, rerecords, source_reads, manual edits with the
   per-run-value exclusion, preamble_repetitions, python_json_parses) —
   they are the comparison currency; wall/tokens are noisy.
