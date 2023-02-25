######################################
# VPC Configuration
######################################
resource "aws_vpc" "vpc" {
  cidr_block           = var.cidr.vpc
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.prefix}-vpc"
  }
}

######################################
# Public Subnet Configuration
######################################
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${local.prefix}-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${local.prefix}-public-rtb"
  }
}

resource "aws_route" "public_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = "${data.aws_region.current.name}a"
  cidr_block        = var.cidr.public_a

  tags = {
    Name = "${local.prefix}-public-subnet-a"
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_subnet" "public_c" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = "${data.aws_region.current.name}c"
  cidr_block        = var.cidr.public_c

  tags = {
    Name = "${local.prefix}-public-subnet-c"
  }
}

resource "aws_route_table_association" "public_c" {
  subnet_id      = aws_subnet.public_c.id
  route_table_id = aws_route_table.public.id
}

######################################
# Private Subnet Configuration
######################################
# ap-northeast-1a
resource "aws_eip" "natgw_a" {
  vpc = true

  tags = {
    Name = "${local.prefix}-eip-a"
  }
}

resource "aws_nat_gateway" "natgw_a" {
  allocation_id = aws_eip.natgw_a.id
  subnet_id     = aws_subnet.public_a.id

  tags = {
    Name = "${local.prefix}-natgw-a"
  }

  depends_on = [
    aws_internet_gateway.igw
  ]
}

resource "aws_route_table" "private_a" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${local.prefix}-private-rtb-a"
  }
}

resource "aws_route" "private_a_natgw" {
  route_table_id         = aws_route_table.private_a.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.natgw_a.id
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = "${data.aws_region.current.name}a"
  cidr_block        = var.cidr.private_a

  tags = {
    Name = "${local.prefix}-private-subnet-a"
  }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private_a.id
}

# ap-northeast-1c
resource "aws_eip" "natgw_c" {
  vpc = true

  tags = {
    Name = "${local.prefix}-eip-a"
  }
}

resource "aws_nat_gateway" "natgw_c" {
  allocation_id = aws_eip.natgw_c.id
  subnet_id     = aws_subnet.public_c.id

  tags = {
    Name = "${local.prefix}-natgw-c"
  }

  depends_on = [
    aws_internet_gateway.igw
  ]
}

resource "aws_route_table" "private_c" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${local.prefix}-private-rtb-c"
  }
}

resource "aws_route" "private_c_natgw" {
  route_table_id         = aws_route_table.private_c.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.natgw_c.id
}

resource "aws_subnet" "private_c" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = "${data.aws_region.current.name}c"
  cidr_block        = var.cidr.private_c

  tags = {
    Name = "${local.prefix}-private-subnet-c"
  }
}

resource "aws_route_table_association" "private_c" {
  subnet_id      = aws_subnet.private_c.id
  route_table_id = aws_route_table.private_c.id
}

######################################
# VPC Endpoint (Gateway) Configuration
######################################
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.vpc.id
  vpc_endpoint_type = "Gateway"
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  policy            = file("${path.module}/iam_policy_document/vpc_endpoint_default.json")

  tags = {
    Name = "${local.prefix}-s3-vpce"
  }
}

resource "aws_vpc_endpoint_route_table_association" "private_a" {
  vpc_endpoint_id = aws_vpc_endpoint.s3.id
  route_table_id  = aws_route_table.private_a.id
}

resource "aws_vpc_endpoint_route_table_association" "private_c" {
  vpc_endpoint_id = aws_vpc_endpoint.s3.id
  route_table_id  = aws_route_table.private_c.id
}