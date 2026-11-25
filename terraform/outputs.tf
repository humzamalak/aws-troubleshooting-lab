output "url" {
  value = "http://${aws_instance.web.public_ip}/"
}

output "instance_id" {
  value = aws_instance.web.id
}

output "scenario" {
  description = "Hidden when scenario = random, so you have to find it."
  value       = var.scenario == "random" ? "random (hidden)" : var.scenario
}

output "hidden_fault" {
  description = "Run: terraform output -raw hidden_fault  (only after you have solved it)."
  value       = local.active
  sensitive   = true
}

output "bucket" {
  value = aws_s3_bucket.content.id
}

output "vpc_id" {
  value = aws_vpc.lab.id
}

output "flow_log_group" {
  value = aws_cloudwatch_log_group.flow.name
}
