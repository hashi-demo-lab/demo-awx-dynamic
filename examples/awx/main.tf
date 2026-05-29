terraform {
  required_providers {
    dynamic = { source = "hashi-demo-lab/dynamic" }
  }
}

provider "dynamic" {}

# ---- Resources (full CRUD) ----

resource "dynamic_awx_organization" "org" {
  name        = "apeval-fresh-org-tf"
  description = "fresh agentprovider build org via terraform"
  max_hosts   = 0
}

resource "dynamic_awx_inventory" "inv" {
  name         = "apeval-fresh-inv-tf"
  description  = "fresh agentprovider build inventory via terraform"
  organization = dynamic_awx_organization.org.id
}

resource "dynamic_awx_host" "host" {
  name        = "apeval-fresh-host-tf"
  description = "fresh agentprovider build host via terraform"
  inventory   = dynamic_awx_inventory.inv.id
  enabled     = true
}

resource "dynamic_awx_job_template" "jt" {
  name      = "apeval-fresh-jt-tf"
  job_type  = "run"
  inventory = dynamic_awx_inventory.inv.id
  project   = 6
  playbook  = "hello_world.yml"
}

# ---- Data source: look up an existing job template by id ----

data "dynamic_awx_job_template_ds" "fixture" {
  id = "70"
}

# ---- Actions ----
# awx_job_launch targets job template 70 (a stable fixture); aap_workflow_job_launch
# targets workflow_job_template 56. Triggered from a sibling host (NOT the action
# targets) to avoid a resource -> action -> resource cycle.

action "dynamic_awx_job_launch" "run_jt" {
  config {
    template_id = 70
  }
}

action "dynamic_aap_workflow_job_launch" "run_wf" {
  config {
    workflow_template_id = 56
  }
}

resource "dynamic_awx_host" "trigger_host" {
  name        = "apeval-fresh-trigger-tf"
  description = "carries action triggers; sibling of action targets"
  inventory   = dynamic_awx_inventory.inv.id
  enabled     = true

  lifecycle {
    action_trigger {
      events  = [after_create]
      actions = [action.dynamic_awx_job_launch.run_jt]
    }
    action_trigger {
      events  = [after_create]
      actions = [action.dynamic_aap_workflow_job_launch.run_wf]
    }
  }
}

# ---- Outputs ----

output "org_id" { value = dynamic_awx_organization.org.id }
output "inventory_id" { value = dynamic_awx_inventory.inv.id }
output "host_id" { value = dynamic_awx_host.host.id }
output "job_template_id" { value = dynamic_awx_job_template.jt.id }
output "ds_jt_name" { value = data.dynamic_awx_job_template_ds.fixture.name }
output "ds_jt_status" { value = data.dynamic_awx_job_template_ds.fixture.status }
