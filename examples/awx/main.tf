terraform {
  required_providers {
    dynamic = { source = "hashi-demo-lab/dynamic" }
  }
}

provider "dynamic" {}

# ---- Resources (full CRUD) ----

resource "dynamic_awx_organization" "org" {
  name        = "apeval-r11-org-tf"
  description = "agentprovider eval r11 org via terraform"
  max_hosts   = 0
}

resource "dynamic_awx_inventory" "inv" {
  name                            = "apeval-r11-inv-tf"
  description                     = "agentprovider eval r11 inventory via terraform"
  organization                    = dynamic_awx_organization.org.id
  kind                            = ""
  variables                       = ""
  prevent_instance_group_fallback = false
}

resource "dynamic_awx_host" "host" {
  name        = "apeval-r11-host-tf"
  description = "agentprovider eval r11 host via terraform"
  inventory   = dynamic_awx_inventory.inv.id
  enabled     = true
  instance_id = ""
  variables   = ""
}

resource "dynamic_awx_job_template" "jt" {
  name        = "apeval-r11-jt-tf"
  description = "agentprovider eval r11 job template via terraform"
  job_type    = "run"
  inventory   = dynamic_awx_inventory.inv.id
  project     = 6
  playbook    = "hello_world.yml"
}

# ---- Data source: look up an existing job template by id ----

data "dynamic_awx_job_template_ds" "fixture" {
  id = "70"
}

# ---- Actions ----
# awx_job_launch targets the JT we created; trigger it from the sibling host
# (a resource OTHER than the action target) to avoid a resource->action->resource cycle.

action "dynamic_awx_job_launch" "run_jt" {
  config {
    template_id = dynamic_awx_job_template.jt.id
  }
}

# aap_workflow_job_launch targets the pre-existing workflow_job_template fixture (id 56);
# trigger it from the org resource (a sibling, not the action's target).

action "dynamic_aap_workflow_job_launch" "run_wf" {
  config {
    workflow_template_id = 56
  }
}

resource "dynamic_awx_host" "trigger_host" {
  name        = "apeval-r11-trigger-tf"
  description = "carries action triggers; sibling of action targets"
  inventory   = dynamic_awx_inventory.inv.id
  enabled     = true
  instance_id = ""
  variables   = ""

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
