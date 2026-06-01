# Codex-scored AWX lean eval prompt

You are evaluating the current `agentprovider` skill and CLI from the current
checkout. Do not modify tracked files.

This is a command-harness measurement, not an investigation. Do not inspect
memory, source files, docs, git status, or generated workspaces unless the
harness command fails. Do not load or read any skill files, including
`.agents/skills/agentprovider/SKILL.md`; the harness is the evaluation surface.
The harness prints the full metrics JSON to stdout at the end. Use that stdout
JSON directly; do not run a second command or read `metrics.json` unless the
harness output is missing the metrics payload.

Run the repeatable lean AWX harness from the repository root:

```bash
RUN_TAG=codexscore-$(date +%Y%m%d%H%M%S) sh .agents/skills/agentprovider/scripts/run_awx_lean_eval.sh
```

Then report only:

- the metrics file path
- wall_seconds
- record_iterations
- conform_iterations
- rerecord_count
- source_reads
- manual_scaffold_edits
- proof_quality
- cleanup_status

Do not print `.env`, token values, password values, cassettes, Terraform state,
or any credential-bearing file contents.
