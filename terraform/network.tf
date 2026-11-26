resource "aws_vpc" "lab" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "troubleshooting-lab" }
}

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.lab.id
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id
  tags   = { Name = "troubleshooting-lab" }
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.lab.id
  cidr_block        = "10.42.1.0/24"
  availability_zone = "${var.region}a"
  tags              = { Name = "lab-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id
  tags   = { Name = "lab-public" }
}

# FAULT missing-igw-route: this route is left out.
resource "aws_route" "default" {
  count                  = local.broken_route ? 0 : 1
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.lab.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# A custom NACL, so the lab can break it without touching the default one.
resource "aws_network_acl" "public" {
  vpc_id     = aws_vpc.lab.id
  subnet_ids = [aws_subnet.public.id]
  tags       = { Name = "lab-public" }
}

resource "aws_network_acl_rule" "in_http" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.my_ip_cidr
  from_port      = 80
  to_port        = 80
}

# Return traffic for the instance's own outbound calls (S3, SSM, updates).
resource "aws_network_acl_rule" "in_ephemeral" {
  #checkov:skip=CKV_AWS_231:Ephemeral return traffic; the security group still blocks inbound 3389.
  network_acl_id = aws_network_acl.public.id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "out_https" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}

# FAULT nacl-ephemeral: NACLs are stateless. Without this rule the web
# server's replies to the client's ephemeral port are dropped.
resource "aws_network_acl_rule" "out_ephemeral" {
  count          = local.broken_nacl ? 0 : 1
  network_acl_id = aws_network_acl.public.id
  rule_number    = 110
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.my_ip_cidr
  from_port      = 1024
  to_port        = 65535
}

# Flow logs show REJECT records, which is the main clue for NACL faults.
resource "aws_cloudwatch_log_group" "flow" {
  #checkov:skip=CKV_AWS_158:Lab data only; default encryption.
  #checkov:skip=CKV_AWS_338:Lab logs are kept for 7 days only.
  name              = "/lab/vpc-flow-logs"
  retention_in_days = 7
}

resource "aws_iam_role" "flow" {
  name = "lab-vpc-flow-logs"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "flow" {
  name = "write-flow-logs"
  role = aws_iam_role.flow.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
      Resource = "${aws_cloudwatch_log_group.flow.arn}:*"
    }]
  })
}

resource "aws_flow_log" "lab" {
  vpc_id                   = aws_vpc.lab.id
  traffic_type             = "ALL"
  log_destination          = aws_cloudwatch_log_group.flow.arn
  iam_role_arn             = aws_iam_role.flow.arn
  max_aggregation_interval = 60
}

# ------------------------------------------------------- security group

resource "aws_security_group" "web" {
  name        = "lab-web"
  description = "Lab web server"
  vpc_id      = aws_vpc.lab.id
}

# FAULT sg-wrong-port: the rule opens 8080, but the server listens on 80.
resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.web.id
  description       = "HTTP from my IP"
  cidr_ipv4         = var.my_ip_cidr
  ip_protocol       = "tcp"
  from_port         = local.broken_sg ? 8080 : 80
  to_port           = local.broken_sg ? 8080 : 80
}

resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.web.id
  description       = "HTTPS to S3 and SSM"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}
