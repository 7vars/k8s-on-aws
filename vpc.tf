terraform {
    backend "s3" { }
}

provider "aws" {
    region = var.region
}

resource "aws_vpc" "vpc" {
    cidr_block = local.vpc_cidr
    enable_dns_support = true
    enable_dns_hostnames = true
    tags = {
        "Name" = "vpc-${var.cluster_name}"
        "Environment" = var.cluster_name
    }
}

resource "aws_subnet" "public_subnet" {
    count = length(local.public_subnet)
    vpc_id = aws_vpc.vpc.id
    cidr_block = local.public_subnet["n${count.index}"].cidr_block
    map_public_ip_on_launch = "true"
    availability_zone = local.public_subnet["n${count.index}"].availablility_zone
    tags = {
        "Name" = "k8s-public-subnet-${var.cluster_name}-${count.index}"
        "Environment" = var.cluster_name
    }
}

resource "aws_subnet" "cluster_subnet" {
    count = length(local.cluster_subnet)
    vpc_id = aws_vpc.vpc.id
    cidr_block = local.cluster_subnet["n${count.index}"].cidr_block
    map_public_ip_on_launch = "false"
    availability_zone = local.cluster_subnet["n${count.index}"].availablility_zone
    tags = {
        "Name" = "k8s-cluster-subnet-${var.cluster_name}-${count.index}"
        "Environment" = var.cluster_name
        "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    }
}

resource "aws_internet_gateway" "igw" {
    vpc_id = aws_vpc.vpc.id
    tags = {
        "Name" = "vpc-igw-${var.cluster_name}"
        "Environment" = var.cluster_name
    }
}

resource "aws_eip" "k8s_cluster_nat_eip" {
    count = length(aws_subnet.public_subnet)
    vpc = true
}

resource "aws_route_table" "rtb_igw" {
    vpc_id = aws_vpc.vpc.id
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.igw.id
    }

    tags = {
        "Name" = "rtb_igw"
        "Environment" = var.cluster_name
    }
}

resource "aws_route_table_association" "rta_igw_public" {
    count = length(local.public_subnet)
    subnet_id = aws_subnet.public_subnet.*.id[count.index]
    route_table_id = aws_route_table.rtb_igw.id
}

resource "aws_nat_gateway" "cluster_nat_gw" {
    count = length(aws_subnet.public_subnet)
    allocation_id = aws_eip.k8s_cluster_nat_eip.*.id[count.index]
    subnet_id = aws_subnet.public_subnet.*.id[count.index]
    depends_on = [aws_internet_gateway.igw]
    tags = {
        "Name" = "nat-gateway-${var.cluster_name}"
        "Environment" = var.cluster_name
    }
}

resource "aws_route_table" "rtb_cluster_nat" {
    count = length(aws_subnet.public_subnet)
    vpc_id = aws_vpc.vpc.id
    route {
        cidr_block = "0.0.0.0/0"
        nat_gateway_id = aws_nat_gateway.cluster_nat_gw.*.id[count.index]
    }
    tags = {
        "Name" = "rtb-cluster-nat-${var.cluster_name}.${aws_subnet.public_subnet.*.availability_zone[count.index]}"
        "Environment" = var.cluster_name
    }
}

resource "aws_route_table_association" "rta_rtb_cluster_nat" {
    count = length(aws_subnet.cluster_subnet)
    route_table_id = aws_route_table.rtb_cluster_nat.*.id[count.index]
    subnet_id = aws_subnet.cluster_subnet.*.id[count.index]
}