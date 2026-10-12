
### creating VPC 

resource "aws_vpc" "april_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "april-vpc"
  }
}

############## PUBLIC AREA #######
### public-subnet 
resource "aws_subnet" "public_subnet_1" {
  vpc_id            = aws_vpc.april_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "${var.aws_region}a"
  tags = {
    Name = "public_subnet_1"
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id            = aws_vpc.april_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.aws_region}b"
  tags = {
    Name = "public_subnet_2"
  }
}

### route table creation for public subnet
resource "aws_route_table" "pub_rt" {
  vpc_id = aws_vpc.april_vpc.id
  tags = {
    Name = "pub_rt"
  }
}

### private route table association for public subnets
resource "aws_route_table_association" "pub_rt_rout1" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.pub_rt.id
}

resource "aws_route_table_association" "pub_rt_rout2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.pub_rt.id
}

### pub route table rule to INTERNET GW 
resource "aws_route" "public_route_rule" {
  route_table_id         = aws_route_table.pub_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.april_internet_gateway.id
}


########## PRIVATE AREA ##############
### private - subnets
resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.april_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "${var.aws_region}a"
  tags = {
    Name = "private_subnet_1"
  }
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.april_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "${var.aws_region}a"
  tags = {
    Name = "private_subnet_2"
  }
}

### route table creation for private subnet
resource "aws_route_table" "pvt_rt" {
  vpc_id = aws_vpc.april_vpc.id
  tags = {
    Name = "pvt_rt"
  }
}

### private route table association for pvt subnets
resource "aws_route_table_association" "pvt_rt_rout1" {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.pvt_rt.id
}

resource "aws_route_table_association" "pvt_rt_rout2" {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.pvt_rt.id
}

### pvt route table rule to NAT GW 
resource "aws_route" "pvt_route_rule" {
  route_table_id         = aws_route_table.pvt_rt.id
  nat_gateway_id         = aws_nat_gateway.april_natgw.id
  destination_cidr_block = "0.0.0.0/0"
}


###### RDS #########
### RDS private subnets
resource "aws_subnet" "rds_subnet_1" {
  vpc_id            = aws_vpc.april_vpc.id
  cidr_block        = "10.0.5.0/24"
  availability_zone = "${var.aws_region}a"
  tags = {
    Name = "rds_subnet_1"
  }
}

resource "aws_subnet" "rds_subnet_2" {
  vpc_id            = aws_vpc.april_vpc.id
  cidr_block        = "10.0.6.0/24"
  availability_zone = "${var.aws_region}b"
  tags = {
    Name = "rds_subnet_1"
  }
}

# ### route table creation for rds pvt subnet
# resource "aws_route_table" "rds_pvt_rt" {
#   vpc_id = aws_vpc.april_vpc.id
#   tags = {
#     Name = "rds_pvt_rt"
#   }
# }

# ### private route table association for rds pvt subnets
# resource "aws_route_table_association" "pvt_rt_rout1" {
#   subnet_id      = aws_subnet.rds_subnet_1.id
#   route_table_id = aws_route_table.rds_pvt_rt.id
# }

# resource "aws_route_table_association" "pvt_rt_rout2" {
#   subnet_id      = aws_subnet.rds_subnet_2.id
#   route_table_id = aws_route_table.rds_pvt_rt.id
# }


### internet gateway
resource "aws_internet_gateway" "april_internet_gateway" {
  vpc_id = aws_vpc.april_vpc.id
  tags = {
    Name = "april-internet-gateway"
  }
}

### elastic ip for NAT Gateway
resource "aws_eip" "eip_nat" {
  domain = "vpc"
  tags = {
    Name = "april-nat-eip"
  }
}

### NAT Gateway
resource "aws_nat_gateway" "april_natgw" {
  allocation_id = aws_eip.eip_nat.id
  subnet_id     = aws_subnet.public_subnet_2.id
  tags = {
    Name = "april-NAT"
  }
}

