terraform {
  required_providers {
    dynamic = { source = "hashi-demo-lab/dynamic" }
  }
}

provider "dynamic" {}

# --- managed resources ---

resource "dynamic_aap_organization" "org" {
  name        = "apeval-r7-105114-tf-org"
  description = "apeval-r7-105114 eval org"
}

resource "dynamic_aap_inventory" "inv" {
  name         = "apeval-r7-105114-tf-inv"
  description  = "apeval-r7-105114 eval inventory"
  organization = dynamic_aap_organization.org.id
}

resource "dynamic_aap_host" "host" {
  name      = "apeval-r7-105114-tf-host"
  inventory = dynamic_aap_inventory.inv.id

  lifecycle {
    action_trigger {
      events  = [after_create]
      actions = [action.dynamic_aap_job_launch.launch_demo]
    }
    action_trigger {
      events  = [after_create]
      actions = [action.dynamic_aap_workflow_job_launch.launch_demo_wf]
    }
  }
}

resource "dynamic_aap_job_template" "jt" {
  name      = "apeval-r7-105114-tf-jt"
  project   = 6
  inventory = dynamic_aap_inventory.inv.id
  playbook  = "hello_world.yml"
}

# --- data source ---

data "dynamic_aap_job_template_ds" "existing" {
  id = 7
}

# --- actions ---

action "dynamic_aap_job_launch" "launch_demo" {
  config {
    job_template_id = "7"
  }
}

action "dynamic_aap_workflow_job_launch" "launch_demo_wf" {
  config {
    workflow_job_template_id = "56"
  }
}

# --- outputs ---

output "existing_jt_url" {
  value = data.dynamic_aap_job_template_ds.existing.url
}

output "org_id" {
  value = dynamic_aap_organization.org.id
}

output "inventory_id" {
  value = dynamic_aap_inventory.inv.id
}

output "host_id" {
  value = dynamic_aap_host.host.id
}

output "job_template_id" {
  value = dynamic_aap_job_template.jt.id
}
