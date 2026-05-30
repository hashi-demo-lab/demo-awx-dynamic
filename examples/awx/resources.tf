terraform {
  required_providers {
    dynamic = { source = "hashi-demo-lab/dynamic" }
  }
}

provider "dynamic" {}

# ---------------------------------------------------------------------------
# Phase A: create the AWX object graph from the proven agentprovider contracts.
# Credentials come from ${env.AWX_USERNAME}/${env.AWX_PASSWORD}; base_url from
# ${env.AWX} (resolved per-contract). No per-API Go — the single dynamic
# provider interprets the YAML contracts in apply-contracts/ at runtime.
# ---------------------------------------------------------------------------

resource "dynamic_organization" "demo" {
  name        = "ap-demo-org"
  description = "agentprovider demo organization"
}

resource "dynamic_inventory" "demo" {
  name         = "ap-demo-inventory"
  description  = "agentprovider demo inventory"
  organization = dynamic_organization.demo.id
}

# localhost with a local connection so hello_world.yml runs green on the control node
resource "dynamic_host" "localhost" {
  name      = "localhost"
  inventory = dynamic_inventory.demo.id
  enabled   = true
  variables = jsonencode({ ansible_connection = "local" })
}

resource "dynamic_group" "demo" {
  name      = "ap-demo-group"
  inventory = dynamic_inventory.demo.id
}

# git project -> AWX syncs it async after create (we poll for "successful" before launch)
resource "dynamic_project" "demo" {
  name         = "ap-demo-project"
  organization = dynamic_organization.demo.id
  scm_type     = "git"
  scm_url      = "https://github.com/ansible/ansible-tower-samples.git"
}

resource "dynamic_job_template" "demo" {
  name      = "ap-demo-job-template"
  job_type  = "run"
  inventory = dynamic_inventory.demo.id
  project   = dynamic_project.demo.id
  playbook  = "hello_world.yml"
}

resource "dynamic_workflow_job_template" "demo" {
  name         = "ap-demo-workflow"
  organization = dynamic_organization.demo.id
}

resource "dynamic_team" "demo" {
  name         = "ap-demo-team"
  organization = dynamic_organization.demo.id
}

resource "dynamic_credential" "demo" {
  name            = "ap-demo-credential"
  credential_type = 1 # Machine
  organization    = dynamic_organization.demo.id
}

resource "dynamic_schedule" "demo" {
  name                  = "ap-demo-schedule"
  unified_job_template  = dynamic_job_template.demo.id
  rrule                 = "DTSTART:20300101T000000Z RRULE:FREQ=DAILY;INTERVAL=1"
}

output "org_id" { value = dynamic_organization.demo.id }
output "job_template_id" { value = dynamic_job_template.demo.id }
output "workflow_job_template_id" { value = dynamic_workflow_job_template.demo.id }
