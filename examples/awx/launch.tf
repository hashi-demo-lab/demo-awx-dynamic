# ---------------------------------------------------------------------------
# Phase B: launch a real job and a real workflow using the created resources.
# Each action-only contract surfaces as a Terraform Action. The actions fire
# from a fresh "launchpad" resource's after_create trigger. The trigger lives on
# a sibling (a group) — NOT on the job_template / workflow it targets — so there
# is no resource -> action -> resource cycle.
# ---------------------------------------------------------------------------

action "dynamic_job_launch" "demo" {
  config {
    template_id = dynamic_job_template.demo.id
  }
}

action "dynamic_workflow_job_launch" "demo" {
  config {
    workflow_job_template_id = dynamic_workflow_job_template.demo.id
  }
}

resource "dynamic_group" "launchpad" {
  name      = "ap-demo-launchpad"
  inventory = dynamic_inventory.demo.id

  lifecycle {
    action_trigger {
      events  = [after_create]
      actions = [
        action.dynamic_job_launch.demo,
        action.dynamic_workflow_job_launch.demo,
      ]
    }
  }
}
