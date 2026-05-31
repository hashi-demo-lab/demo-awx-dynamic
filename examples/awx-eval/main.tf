terraform {
  required_providers {
    dynamic = { source = "hashi-demo-lab/dynamic" }
  }
}
provider "dynamic" {}

resource "dynamic_aap_organization" "demo" {
  name        = "apr3-tf-org"
  description = "round-3 eval org"
}
resource "dynamic_aap_inventory" "demo" {
  name         = "apr3-tf-inv"
  description  = "round-3 eval inventory"
  organization = dynamic_aap_organization.demo.id
}
resource "dynamic_aap_host" "localhost" {
  name      = "localhost"
  inventory = dynamic_aap_inventory.demo.id
  enabled   = true
  variables = jsonencode({ ansible_connection = "local" })
  lifecycle {
    action_trigger {
      events  = [after_create]
      actions = [
        action.dynamic_aap_job_launch.demo,
        action.dynamic_aap_workflow_job_launch.demo,
      ]
    }
  }
}
resource "dynamic_aap_job_template" "demo" {
  name      = "apr3-tf-jt"
  job_type  = "run"
  inventory = dynamic_aap_inventory.demo.id
  project   = 6
  playbook  = "hello_world.yml"
}
action "dynamic_aap_job_launch" "demo" {
  config { template_id = dynamic_aap_job_template.demo.id }
}
action "dynamic_aap_workflow_job_launch" "demo" {
  config { workflow_job_template_id = 176 }
}
output "jt_id" { value = dynamic_aap_job_template.demo.id }
