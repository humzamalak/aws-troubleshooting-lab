variable "region" {
  type    = string
  default = "eu-west-2"
}

variable "my_ip_cidr" {
  description = "Your public IP as a /32, for example 203.0.113.7/32. Only this address can reach the lab web server."
  type        = string

  validation {
    condition     = can(cidrhost(var.my_ip_cidr, 0)) && var.my_ip_cidr != "0.0.0.0/0"
    error_message = "my_ip_cidr must be a valid CIDR and must not be 0.0.0.0/0."
  }
}

variable "scenario" {
  description = <<-EOT
    Which fault to inject:
      healthy            everything works
      missing-igw-route  public route table has no default route
      nacl-ephemeral     network ACL blocks return traffic
      sg-wrong-port      security group opens the wrong port
      iam-object-arn     IAM policy names the bucket, not the objects
      random             one of the four faults, picked at random and not shown
  EOT
  type        = string
  default     = "healthy"

  validation {
    condition     = contains(["healthy", "missing-igw-route", "nacl-ephemeral", "sg-wrong-port", "iam-object-arn", "random"], var.scenario)
    error_message = "Unknown scenario. See the variable description."
  }
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}
