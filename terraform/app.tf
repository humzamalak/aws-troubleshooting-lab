# ------------------------------------------------------------- S3 content

resource "aws_s3_bucket" "content" {
  #checkov:skip=CKV_AWS_144:Lab bucket; no replication.
  #checkov:skip=CKV2_AWS_62:No event notifications needed.
  #checkov:skip=CKV_AWS_18:No access logging for a lab bucket.
  #checkov:skip=CKV_AWS_21:No versioning for a lab bucket.
  #checkov:skip=CKV2_AWS_61:Objects are deleted with the lab.
  #checkov:skip=CKV_AWS_145:SSE-S3 is enough for lab content.
  bucket_prefix = "troubleshooting-lab-"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "content" {
  bucket                  = aws_s3_bucket.content.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "content" {
  bucket = aws_s3_bucket.content.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_object" "message" {
  bucket       = aws_s3_bucket.content.id
  key          = "message.txt"
  content      = "Hello from S3. If you can read this in the browser, every layer works."
  content_type = "text/plain"
}

# ------------------------------------------------------------------- IAM

resource "aws_iam_role" "web" {
  name = "lab-web-instance"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Session Manager access, so no SSH key or port 22 is needed.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.web.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# FAULT iam-object-arn: s3:GetObject acts on objects ("bucket/*"), not on the
# bucket ARN. With only the bucket ARN, every GetObject is AccessDenied.
resource "aws_iam_role_policy" "read_content" {
  name = "read-lab-content"
  role = aws_iam_role.web.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "s3:GetObject"
      Resource = local.broken_iam ? aws_s3_bucket.content.arn : "${aws_s3_bucket.content.arn}/*"
    }]
  })
}

resource "aws_iam_instance_profile" "web" {
  name = "lab-web-instance"
  role = aws_iam_role.web.name
}

# ---------------------------------------------------------------- EC2

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "web" {
  #checkov:skip=CKV_AWS_88:A public IP is part of the lab; access is limited to my_ip_cidr.
  #checkov:skip=CKV_AWS_126:Detailed monitoring is not needed for a lab.
  #checkov:skip=CKV_AWS_135:t3 instances are EBS-optimised by default.
  #checkov:skip=CKV2_AWS_41:An instance profile is attached.
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.web.id]
  iam_instance_profile        = aws_iam_instance_profile.web.name
  associate_public_ip_address = true

  # The server uses only software that ships with Amazon Linux 2023
  # (python3 and the AWS CLI), so it starts even when the network is broken.
  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/files/user_data.sh.tftpl", {
    bucket = aws_s3_bucket.content.id
    region = var.region
    server = file("${path.module}/files/server.py")
  })

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 8
  }

  tags = { Name = "lab-web" }
}
