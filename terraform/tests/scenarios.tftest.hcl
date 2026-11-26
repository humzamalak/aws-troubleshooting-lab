# Tests with mocked providers: no AWS account needed.
# Run: terraform init && terraform test

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { value = "ami-0123456789abcdef0" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:eu-west-2:111122223333:log-group:/lab/vpc-flow-logs" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111122223333:role/lab" }
  }
  mock_resource "aws_iam_instance_profile" {
    defaults = { arn = "arn:aws:iam::111122223333:instance-profile/lab" }
  }
  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::troubleshooting-lab-test", id = "troubleshooting-lab-test" }
  }
}

mock_provider "random" {}

variables {
  my_ip_cidr = "203.0.113.7/32"
}

run "healthy" {
  command = plan
  variables {
    scenario = "healthy"
  }
  assert {
    condition     = length(aws_route.default) == 1
    error_message = "healthy must have a default route"
  }
  assert {
    condition     = length(aws_network_acl_rule.out_ephemeral) == 1
    error_message = "healthy must allow ephemeral egress"
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.http.from_port == 80
    error_message = "healthy must open port 80"
  }
}

run "missing_igw_route" {
  command = plan
  variables {
    scenario = "missing-igw-route"
  }
  assert {
    condition     = length(aws_route.default) == 0
    error_message = "the default route must be missing"
  }
  assert {
    condition     = length(aws_network_acl_rule.out_ephemeral) == 1 && aws_vpc_security_group_ingress_rule.http.from_port == 80
    error_message = "only one fault may be active"
  }
}

run "nacl_ephemeral" {
  command = plan
  variables {
    scenario = "nacl-ephemeral"
  }
  assert {
    condition     = length(aws_network_acl_rule.out_ephemeral) == 0
    error_message = "the ephemeral egress rule must be missing"
  }
  assert {
    condition     = length(aws_route.default) == 1
    error_message = "only one fault may be active"
  }
}

run "sg_wrong_port" {
  command = plan
  variables {
    scenario = "sg-wrong-port"
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.http.from_port == 8080
    error_message = "the security group must open 8080"
  }
}

run "iam_object_arn" {
  # apply against the mock providers, so the policy JSON is known
  command = apply
  variables {
    scenario = "iam-object-arn"
  }
  assert {
    condition     = jsondecode(aws_iam_role_policy.read_content.policy).Statement[0].Resource == "arn:aws:s3:::troubleshooting-lab-test"
    error_message = "the policy must name the bucket ARN only"
  }
}

run "healthy_iam" {
  command = apply
  variables {
    scenario = "healthy"
  }
  assert {
    condition     = jsondecode(aws_iam_role_policy.read_content.policy).Statement[0].Resource == "arn:aws:s3:::troubleshooting-lab-test/*"
    error_message = "healthy must grant GetObject on bucket/*"
  }
}

run "rejects_open_cidr" {
  command = plan
  variables {
    my_ip_cidr = "0.0.0.0/0"
  }
  expect_failures = [var.my_ip_cidr]
}
