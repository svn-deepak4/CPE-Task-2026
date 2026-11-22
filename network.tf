resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.name}-vpc"
  }
}

resource "aws_subnet" "private" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.private_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name}-private-${count.index + 1}"
    Tier = "private"
  }
}

resource "aws_route_table" "private" {
  count = 2

  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name}-private-${count.index + 1}"
  }
}

resource "aws_route_table_association" "private" {
  count = 2

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_security_group" "lambda" {
  name        = "${local.name}-lambda"
  description = "Allow Lambda HTTPS egress to private VPC endpoints."
  vpc_id      = aws_vpc.main.id

  egress {
    description = "HTTPS to interface endpoints in this VPC."
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "${local.name}-lambda"
  }
}

resource "aws_security_group" "endpoints" {
  name        = "${local.name}-endpoints"
  description = "HTTPS ingress from the Lambda security group."
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTPS from Lambda."
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  tags = {
    Name = "${local.name}-endpoints"
  }
}

resource "aws_security_group" "alb" {
  name        = "${local.name}-alb"
  description = "VPC-only HTTPS access to the internal ALB."
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from explicitly allowed internal client ranges."
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = length(var.allowed_client_cidrs) > 0 ? var.allowed_client_cidrs : [var.vpc_cidr]
  }

  egress = []

  tags = {
    Name = "${local.name}-alb"
  }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset([
    "ssm",
    "logs",
  ])

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${local.name}-${each.key}-endpoint"
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id

  tags = {
    Name = "${local.name}-s3-endpoint"
  }
}
