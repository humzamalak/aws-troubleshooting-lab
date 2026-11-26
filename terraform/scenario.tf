locals {
  faults = ["missing-igw-route", "nacl-ephemeral", "sg-wrong-port", "iam-object-arn"]
}

# Picked once per "random" run. Change the keeper (or taint) to pick again.
resource "random_shuffle" "fault" {
  input        = local.faults
  result_count = 1
  keepers = {
    scenario = var.scenario
  }
}

locals {
  active = var.scenario == "random" ? random_shuffle.fault.result[0] : var.scenario

  broken_route = local.active == "missing-igw-route"
  broken_nacl  = local.active == "nacl-ephemeral"
  broken_sg    = local.active == "sg-wrong-port"
  broken_iam   = local.active == "iam-object-arn"
}
