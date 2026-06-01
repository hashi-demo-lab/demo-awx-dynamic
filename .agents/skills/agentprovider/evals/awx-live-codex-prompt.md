# Codex-scored AWX full-live eval prompt

You are evaluating the current `agentprovider` skill and CLI from the current
checkout. Follow `.agents/skills/agentprovider/evals/awx-live.json` exactly.

Important constraints:

- Run from the repository root.
- Use `docs/awx-api-to-aap-resources.md` for the seven-contract target set.
- Use `agentprovider bootstrap --from-introspect` for action endpoints too when
  live `introspect` produced endpoint metadata. Do not launch a live job only to
  seed an action contract shape; the later `record --allow-mutations` step is the
  proof capture point.
- Create fresh contracts, cassettes, proof sidecars, and Terraform files for this
  run under `/private/tmp/agentprovider-awx-full-${RUN_TAG}`; do not copy existing
  generated examples as the answer key and do not modify tracked repository files.
- Use one `RUN_TAG` for the whole run and name every created AWX object
  `apeval-${RUN_TAG}-*`.
- Keep the provider contract directory to exactly the seven target contracts
  before Terraform validation/apply; temporary discovery contracts must not be
  loaded by the provider.
- Dynamic provider contract `type` values must be unique. Use a distinct
  data-source type such as `job_template_ds` even when the AWX endpoint is the
  same as the `job_template` resource endpoint.
- When re-recording to the same cassette path after a reviewed contract or
  request-shape change, use `record --force`; do not create alternate cassette
  paths for the same contract.
- Preserve `lifecycle.update.refresh_after: true` from `bootstrap --from-introspect`
  resource drafts unless a live update response is known to contain full refreshed
  state. Dropping it causes avoidable `update_then_read_reflects` repair loops on
  partial or empty update responses.
- Do not assert `named_url` for the job-template data source unless the live read
  response actually includes it. `url` is the stable computed output.
- Use `agentprovider prove "$contract" "$cassette" --uplift` as the terminal proof
  gate. `prove` is offline replay: do not add `--base-url`, and do not pass
  `agentprovider introspect --format json` output as `--metadata`. If coverage is
  not proof-ready, classify or model the remaining fields rather than lowering
  proof quality.
- After each successful `record`, run `agentprovider prove --uplift` first. Do not run
  standalone `conform` or `completeness` before `prove` unless the aggregate
  `prove` output lacks enough repair detail. Treat `prove.conform.overall_passed`
  as the conform result and `prove.completeness` as the completeness result for
  resource/data-source contracts.
- Do not print `.env`, token values, password values, cassettes, Terraform state,
  or any credential-bearing file contents.
- Do not report `PROVEN` unless every assertion in `awx-live.json` passes:
  all seven contracts conform, completeness/proof gates are shown, Terraform
  apply succeeds, job and workflow actions launch live AWX jobs, the second plan
  is a no-op, and cleanup is verified.
- If the runtime does not support concurrent sub-runs, execute serially and
  report that as an efficiency caveat rather than skipping any proof gate.
- If `terraform destroy` fails because AWX is still processing events for a
  just-launched job or workflow job, wait briefly and retry destroy before the
  API sweep. Still record the failed attempt and only pass cleanup after destroy
  succeeds or the API sweep verifies zero tagged leftovers.

At the end, report the metric schema fields from `awx-live.json` plus the exact
paths to the generated metrics, contracts, cassettes, proof sidecars, Terraform
workspace, and cleanup evidence.

Also write a machine-readable metrics file at
`/private/tmp/agentprovider-awx-full-${RUN_TAG}/metrics.json` with these keys:
`skill_version`, `cli_version`, `changed_lever`, `token_total`, `wall_seconds`,
`record_iterations`, `conform_iterations`, `rerecord_count`, `source_reads`,
`manual_scaffold_edits`, `proof_quality`, `cleanup_status`, and
`artifact_paths`. Count `manual_scaffold_edits` as avoidable scaffold repair
churn only; do not count deterministic run-specific example values, fixture ids,
or action outputs learned from the first record. Set `token_total` to null
inside this file; the outer scored wrapper captures token telemetry separately.
