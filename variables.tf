variable "cluster_name" {
    default = "develop"
}

variable "cluster_domain" {
    default = "k8s.example.local"
}

variable "vpc_network_index" {
    default = "1"
}

variable "region" {
    default = "eu-central-1"
}

variable "public_domain" {
    default = "k8s.example.com"
}

variable "node_count" {
    default = "3"
}

variable "max_node_count" {
    default = "5"
}

variable "autoscaling_group_name" {
    default = "terraform-tf-eks"
}

variable "whitelisted_hosts" {
    default = []
}

variable "public_key_path" {
    default = "./keys/cluster_key.pub"
}

variable "k8s_version" {
  default = "1.19"
}

variable "node_instance_type" {
    default = "m4.xlarge"
}

locals {
    vpc_cidr = "10.${var.vpc_network_index}.0.0/16"

    public_subnet = {
        n0 = {
            cidr_block = "10.${var.vpc_network_index}.4.0/22"
            availablility_zone = "${var.region}a"
        }
        n1 = {
            cidr_block = "10.${var.vpc_network_index}.8.0/22"
            availablility_zone = "${var.region}b"
        }
        #n2 = {
        #    cidr_block = "10.${var.vpc_network_index}.12.0/22"
        #    availablility_zone = "${var.region}c"
        #}
    }

    cluster_subnet = {
        n0 = {
            cidr_block = "10.${var.vpc_network_index}.32.0/19"
            availablility_zone = "${var.region}a"
        }
        n1 = {
            cidr_block = "10.${var.vpc_network_index}.64.0/19"
            availablility_zone = "${var.region}b"
        }
        #n2 = {
        #    cidr_block = "10.${var.vpc_network_index}.96.0/19"
        #    availablility_zone = "${var.region}c"
        #}
    }
}