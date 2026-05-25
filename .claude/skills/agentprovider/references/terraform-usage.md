# Consuming a proven contract in Terraform (the HCL surface)

Authoring + proving a contract is half the job; the other half is **using** it in
real Terraform. This file is the complete reference for what a contract looks like
from the practitioner side — write the HCL entirely from here. Everything below is
produced at runtime by the single generic `dynamic` provider interpreting your
YAML contracts; you author no per-API code.

## Naming: contract → Terraform identifier

The contract's `type` (and `kind`) determines the Terraform identifier:

| Contract | Becomes | Used in HCL as |
|---|---|---|
| `kind: Resource`, `type: project` (has `create`) | a managed **resource** | `resource "dynamic_project" "x"` |
| `kind: DataSource`, `type: team` | a **data source** | `data "dynamic_team" "x"` |
| `kind: Ephemeral`, `type: session_token` | an **ephemeral resource** | `ephemeral "dynamic_session_token" "x"` |
| `kind: Resource`, `type: job_run`, **action-only** (`actions`, no `create`) | a Terraform **Action** `dynamic_<type>_<verb>` | `action "dynamic_job_run_start" "x"` |

The provider type prefix is always `dynamic_`. An action's identifier is
`dynamic_<type>_<verb>` — contract `type: job_run` with action `start` →
`dynamic_job_run_start`.

## provider block

```hcl
terraform {
  required_providers {
    dynamic = { source = "hashi-demo-lab/dynamic" }
  }
}

provider "dynamic" {
  # The provider reads the YAML contracts in the contracts dir at runtime.
  # base_url / credentials are resolved by each contract via ${var.*} / ${env.*}.
}
```

Use a `dev_overrides` block in a `.terraformrc` / `TF_CLI_CONFIG_FILE` to point at
a locally built provider binary; `dev_overrides` bypasses `terraform init`, so you
go straight to `plan`/`apply`.

## Resources and foreign keys

Attributes map 1:1 to the contract's `schema.attributes`. Wire foreign keys
through **computed ids** so Terraform builds the dependency graph automatically:

```hcl
resource "dynamic_team" "main" {
  name = "platform"
}

resource "dynamic_project" "app" {
  name = "checkout-service"
  team = dynamic_team.main.id   # FK via computed id
}
```

A `type: number` FK reference like `dynamic_team.main.id` flows in as a number and
renders cleanly into the child contract's paths/bodies.

## Actions and `action_trigger`

An action-only contract surfaces as an `action` block whose `config` carries the
action's input attributes:

```hcl
action "dynamic_job_run_start" "deploy" {
  config {
    pipeline_id = dynamic_pipeline.release.id
  }
}
```

An action does nothing on its own — it runs when a resource's lifecycle triggers
it via `action_trigger`:

```hcl
resource "dynamic_runner" "ci" {
  name    = "linux-runner"
  project = dynamic_project.app.id

  lifecycle {
    action_trigger {
      events  = [after_create]                            # before_create | after_create | before_update | after_update
      actions = [action.dynamic_job_run_start.deploy]
    }
  }
}
```

**Cycle gotcha (important).** Attach the trigger to a resource *other than* the one
the action targets. If the action runs off `dynamic_pipeline.release` and you also
put the `action_trigger` on that same pipeline, you create a
`resource → action → resource` self-cycle and Terraform errors. In the example the
trigger lives on the **runner** (a sibling under the same project), so the action
fires after the graph is built without a cycle.

## A complete graph

```
team ──▶ project ──┬─▶ runner ──(after_create)──▶ action: start job run
                   └─▶ pipeline ◀── (action targets this)
```

`terraform apply` then creates the four resources in dependency order and invokes
the job-run action once the runner is created. `terraform plan` a second time is a
no-op (idempotency), and `terraform destroy` removes all managed resources (the
action created no Terraform-managed object, so there is nothing to destroy for it).

## Where this gets proven

The contract-level proof (`agentprovider conform`) proves each contract against its
cassette offline. The HCL above is the live end-to-end proof: a real `apply` /
re-`plan` / `destroy` against the target. Keep credentials in `${env.*}` /
`${var.*}` (or provider config) — never in the HCL or committed state.
