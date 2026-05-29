terraform {
  required_providers {
    dynamic = { source = "hashi-demo-lab/dynamic" }
  }
}

provider "dynamic" {
  # Contracts are read at runtime from AGENTPROVIDER_CONTRACTS.
  # base_url + credentials come from each contract via ${env.AWX*}.
}

# --- Resources (full CRUD) -------------------------------------------------

resource "dynamic_awx_organization" "org" {
  name        = "apeval-r10-org"
  description = "agentprovider eval r10 organization"
}

resource "dynamic_awx_inventory" "inv" {
  name         = "apeval-r10-inv"
  description  = "agentprovider eval r10 inventory"
  organization = dynamic_awx_organization.org.id # FK via computed id
}

resource "dynamic_awx_host" "host" {
  name        = "apeval-r10-host"
  description = "agentprovider eval r10 host"
  inventory   = dynamic_awx_inventory.inv.id # FK via computed id
  enabled     = true
}

resource "dynamic_awx_job_template" "jt" {
  name        = "apeval-r10-jt"
  description = "agentprovider eval r10 job template"
  job_type    = "run"
  project     = 6 # existing Demo Project
  inventory   = dynamic_awx_inventory.inv.id
  playbook    = "hello_world.yml"

  # behavior + launch-prompt toggles (settable knobs)
  ask_variables_on_launch = true
}

# --- Data source (lookup existing job_template by id) ----------------------

data "dynamic_awx_job_template_ds" "demo" {
  id = "7" # existing Demo Job Template
}

# --- Actions ---------------------------------------------------------------

# awx_job_launch targets existing job_template 7 (Demo)
action "dynamic_awx_job_launch" "demo_launch" {
  config {
    template_id = 7
  }
}

# aap_workflow_job_launch targets existing workflow_job_template 56
action "dynamic_aap_workflow_job_launch" "wf_launch" {
  config {
    workflow_template_id = 56
  }
}

# Triggers live on resources OTHER than the action targets (no cycle):
# the job launch fires after the host is created; the workflow launch
# after the job_template is created.
resource "dynamic_awx_host" "trigger_host" {
  name      = "apeval-r10-host-trigger"
  inventory = dynamic_awx_inventory.inv.id
  enabled   = true

  lifecycle {
    action_trigger {
      events  = [after_create]
      actions = [action.dynamic_awx_job_launch.demo_launch]
    }
  }
}

resource "dynamic_awx_job_template" "trigger_jt" {
  name      = "apeval-r10-jt-trigger"
  job_type  = "run"
  project   = 6
  inventory = dynamic_awx_inventory.inv.id
  playbook  = "hello_world.yml"

  lifecycle {
    action_trigger {
      events  = [after_create]
      actions = [action.dynamic_aap_workflow_job_launch.wf_launch]
    }
  }
}

# --- Outputs ---------------------------------------------------------------

output "organization_id" { value = dynamic_awx_organization.org.id }
output "inventory_id" { value = dynamic_awx_inventory.inv.id }
output "host_id" { value = dynamic_awx_host.host.id }
output "job_template_id" { value = dynamic_awx_job_template.jt.id }
output "data_source_name" { value = data.dynamic_awx_job_template_ds.demo.name }
output "data_source_project" { value = data.dynamic_awx_job_template_ds.demo.project }
