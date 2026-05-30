terraform {
  required_providers {
    dynamic = { source = "hashi-demo-lab/dynamic" }
  }
}

provider "dynamic" {}

# ---- Resources (full CRUD) ----

resource "dynamic_awx_organization" "org" {
  name        = "apeval-eval-org-tf"
  description = "agentprovider AWX live eval org via terraform"
  max_hosts   = 0
}

resource "dynamic_awx_inventory" "inv" {
  name         = "apeval-eval-inv-tf"
  description  = "agentprovider AWX live eval inventory via terraform"
  organization = dynamic_awx_organization.org.id
}

resource "dynamic_awx_host" "host" {
  name        = "apeval-eval-host-tf"
  description = "agentprovider AWX live eval host via terraform"
  inventory   = dynamic_awx_inventory.inv.id
  enabled     = true
}

resource "dynamic_awx_job_template" "jt" {
  name      = "apeval-eval-jt-tf"
  job_type  = "run"
  inventory = dynamic_awx_inventory.inv.id
  project   = 6
  playbook  = "hello_world.yml"
}

# ---- Data source: look up an existing job template by id ----

data "dynamic_awx_job_template_ds" "fixture" {
  id = "70"
}

# ---- Actions (triggered from a sibling host, not the action targets, to avoid a cycle) ----

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
  name        = "apeval-eval-trigger-tf"
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
