provider "aws" {
  region = "us-east-1"

  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  s3_use_path_style           = true

  endpoints {
    ec2   = "http://localhost:4566"
    elbv2 = "http://localhost:4566"
    s3    = "http://localhost:4566"
    sts   = "http://localhost:4566"
  }
}

resource "aws_vpc" "this" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "public_b" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
}

resource "aws_s3_bucket" "open" {
  bucket = "conftest-bad-open"
}

resource "aws_s3_bucket" "half" {
  bucket = "conftest-bad-half"
}

resource "aws_s3_bucket_public_access_block" "half" {
  bucket = aws_s3_bucket.half.bucket

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket" "data" {
  bucket = "conftest-bad-data"
}

resource "aws_s3_bucket" "database" {
  bucket = "conftest-bad-database"
}

resource "aws_s3_bucket_public_access_block" "database" {
  bucket = aws_s3_bucket.database.bucket

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_security_group" "open" {
  name   = "conftest-bad-open"
  vpc_id = aws_vpc.this.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "alb" {
  name   = "conftest-bad-alb"
  vpc_id = aws_vpc.this.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "zero_lb" {
  name   = "conftest-bad-zero-lb"
  vpc_id = aws_vpc.this.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "none" {
  count = 0

  name               = "conftest-bad-none"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.zero_lb.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

resource "aws_security_group" "service" {
  name   = "conftest-bad-service"
  vpc_id = aws_vpc.this.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.this.cidr_block]
  }
}

resource "aws_vpc_security_group_ingress_rule" "open" {
  security_group_id = aws_security_group.service.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_security_group_rule" "legacy_open" {
  type              = "ingress"
  security_group_id = aws_security_group.service.id
  cidr_blocks       = ["0.0.0.0/0"]
  protocol          = "tcp"
  from_port         = 8080
  to_port           = 8080
}

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.this.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
