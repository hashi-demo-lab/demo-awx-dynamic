# AWX API → AAP Terraform Resource Mapping

Maps AWX REST API endpoints to Terraform resource names following the
[`terraform-provider-aap`](https://github.com/ansible/terraform-provider-aap) naming conventions
(`aap_` prefix, snake_case).

## Resources (CRUD)

| AWX API endpoint | Terraform resource | Notes |
|---|---|---|
| `/api/v2/organizations/` | `aap_organization` | data source only in aap provider; full resource in agentprovider |
| `/api/v2/inventories/` | `aap_inventory` | |
| `/api/v2/constructed_inventories/` | `aap_constructed_inventory` | subtype of inventory |
| `/api/v2/hosts/` | `aap_host` | |
| `/api/v2/groups/` | `aap_group` | |
| `/api/v2/job_templates/` | `aap_job_template` | data source only in aap provider |
| `/api/v2/workflow_job_templates/` | `aap_workflow_job_template` | data source only in aap provider |
| `/api/v2/projects/` | `aap_project` | not yet in aap provider |
| `/api/v2/credentials/` | `aap_credential` | not yet in aap provider |
| `/api/v2/credential_types/` | `aap_credential_type` | not yet in aap provider |
| `/api/v2/teams/` | `aap_team` | not yet in aap provider |
| `/api/v2/users/` | `aap_user` | not yet in aap provider |
| `/api/v2/execution_environments/` | `aap_execution_environment` | not yet in aap provider |
| `/api/v2/instance_groups/` | `aap_instance_group` | not yet in aap provider |
| `/api/v2/schedules/` | `aap_schedule` | not yet in aap provider |
| `/api/v2/notification_templates/` | `aap_notification_template` | not yet in aap provider |
| `/api/v2/labels/` | `aap_label` | not yet in aap provider |
| `/api/v2/tokens/` | `aap_token` | not yet in aap provider |
| `/api/v2/inventory_sources/` | `aap_inventory_source` | not yet in aap provider |
| `/api/v2/workflow_job_template_nodes/` | `aap_workflow_job_template_node` | not yet in aap provider |
| `/api/v2/role_definitions/` | `aap_role_definition` | not yet in aap provider |
| `/api/v2/role_user_assignments/` | `aap_role_user_assignment` | not yet in aap provider |
| `/api/v2/role_team_assignments/` | `aap_role_team_assignment` | not yet in aap provider |

## Data Sources (read-only lookup)

| AWX API endpoint | Terraform data source | Notes |
|---|---|---|
| `/api/v2/organizations/` | `aap_organization` | in aap provider |
| `/api/v2/inventories/` | `aap_inventory` | in aap provider |
| `/api/v2/job_templates/` | `aap_job_template` | in aap provider |
| `/api/v2/workflow_job_templates/` | `aap_workflow_job_template` | in aap provider |

## Actions (one-shot, no persistent state)

| AWX API endpoint | Terraform action | Notes |
|---|---|---|
| `/api/v2/job_templates/{id}/launch/` | `aap_job_launch` | in aap provider; POST only |
| `/api/v2/workflow_job_templates/{id}/launch/` | `aap_workflow_job_launch` | in aap provider; POST only |
| `/api/v2/ad_hoc_commands/` | `aap_ad_hoc_command` | not yet in aap provider |
| `/api/v2/job_templates/{id}/copy/` | `aap_job_template_copy` | not yet in aap provider |

## Excluded / read-only endpoints

Endpoints with no practical Terraform resource — observability, system internals, or read-only aggregations:

| AWX API endpoint | Reason |
|---|---|
| `/api/v2/activity_stream/` | read-only audit log |
| `/api/v2/dashboard/` | read-only aggregation |
| `/api/v2/jobs/` | read-only; jobs created via `aap_job_launch` |
| `/api/v2/workflow_jobs/` | read-only; created via `aap_workflow_job_launch` |
| `/api/v2/inventory_updates/` | read-only; sync triggered via `aap_inventory_source` |
| `/api/v2/project_updates/` | read-only; triggered by `aap_project` sync |
| `/api/v2/system_jobs/` | read-only; system-managed |
| `/api/v2/unified_jobs/` | read-only polymorphic index |
| `/api/v2/unified_job_templates/` | read-only polymorphic index |
| `/api/v2/ping/` | health check |
| `/api/v2/config/` | system config, not user-managed |
| `/api/v2/me/` | current user info |
| `/api/v2/metrics/` | Prometheus metrics |
| `/api/v2/analytics/` | telemetry |
| `/api/v2/mesh_visualizer/` | read-only topology |
| `/api/v2/instances/` | read-only infrastructure |
| `/api/v2/host_metrics/` | read-only |
| `/api/v2/host_metric_summary_monthly/` | read-only |
| `/api/v2/bulk/` | internal bulk ops |
| `/api/v2/roles/` | legacy RBAC (superseded by role_definitions) |

## agentprovider contracts in this repo

Target contracts for the demo. Contracts are wiped before each recording run
and rebuilt from scratch by the agent. Add rows here to extend the demo scope.

| Contract file | Terraform type | AWX API | Kind |
|---|---|---|---|
| `organization.yaml` | `aap_organization` | `/api/v2/organizations/` | Resource |
| `inventory.yaml` | `aap_inventory` | `/api/v2/inventories/` | Resource |
| `job_template.yaml` | `aap_job_template` | `/api/v2/job_templates/` | Resource |
| `host.yaml` | `aap_host` | `/api/v2/hosts/` | Resource |
| `group.yaml` | `aap_group` | `/api/v2/groups/` | Resource |
| `project.yaml` | `aap_project` | `/api/v2/projects/` | Resource |
| `credential.yaml` | `aap_credential` | `/api/v2/credentials/` | Resource |
| `team.yaml` | `aap_team` | `/api/v2/teams/` | Resource |
| `workflow_job_template.yaml` | `aap_workflow_job_template` | `/api/v2/workflow_job_templates/` | Resource |
| `schedule.yaml` | `aap_schedule` | `/api/v2/schedules/` | Resource |
| `organization_ds.yaml` | `aap_organization` | `/api/v2/organizations/` | DataSource |
| `inventory_ds.yaml` | `aap_inventory` | `/api/v2/inventories/` | DataSource |
| `job_template_ds.yaml` | `aap_job_template` | `/api/v2/job_templates/` | DataSource |
| `workflow_job_template_ds.yaml` | `aap_workflow_job_template` | `/api/v2/workflow_job_templates/` | DataSource |
| `job_launch.yaml` | `aap_job_launch` | `/api/v2/job_templates/{id}/launch/` | Action |
| `workflow_job_launch.yaml` | `aap_workflow_job_launch` | `/api/v2/workflow_job_templates/{id}/launch/` | Action |
