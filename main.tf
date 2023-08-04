provider "aws" {
  region = "eu-west-1"
}

resource "aws_vpc" "cluster_vpc" {
  cidr_block = var.vpc_cidr_block
}

resource "aws_subnet" "master_subnet" {
  vpc_id                  = aws_vpc.cluster_vpc
  cidr_block              = var.master_subnet_cidr
  availability_zone       = var.master_subnet_az
}

resource "aws_subnet" "worker_subnet" {
  vpc_id                  = aws_vpc.cluster_vpc
  cidr_block              = var.worker_subnet_cidr
  availability_zone       = var.worker_subnet_az
}

resource "aws_security_group" "master_security_group" {
  name_prefix = "Master-SG-"
  vpc_id      = aws_vpc.cluster_vpc

  ingress {
    from_port   = var.master_ingress_port
    to_port     = var.master_ingress_port
    protocol    = var.master_ingress_protocol
    cidr_blocks = [var.master_ingress_cidr]
  }

  egress {
    from_port   = var.master_egress_port
    to_port     = var.master_egress_port
    protocol    = var.master_egress_protocol
    cidr_blocks = [var.master_egress_cidr]
  }
}


resource "aws_security_group" "worker_security_group" {
  name_prefix = "Worker-SG-"
  vpc_id      = aws_vpc.cluster_vpc

  ingress {
    from_port   = var.worker_ingress_port
    to_port     = var.worker_ingress_port
    protocol    = var.worker_ingress_protocol
    cidr_blocks = [var.worker_ingress_cidr]
  }

  egress {
    from_port   = var.worker_egress_port
    to_port     = var.worker_egress_port
    protocol    = var.worker_egress_protocol
    cidr_blocks = [var.worker_egress_cidr]
  }
}

locals {
  serverconfig = [
    for srv in var.vm_config : [
      for i in range(1, srv.no_of_instances+1) : {
        instance_name   = "${srv.node_name}-${i}"
        instance_type   = srv.instance_type
        subnet_id       = srv.subnet_id
        ami             = srv.ami
        security_groups = srv.vpc_security_group_ids
      }
    ]
  ]
}

locals {
  instances = flatten(local.serverconfig)
}

resource "aws_instance" "kubeadm" {
  for_each               = {for server in local.instances: server.instance_name => server}
  ami                    = each.value.ami
  instance_type          = each.value.instance_type
  security_groups        = each.value.security_groups_ids
  key_name               = var.key_name
  subnet_id              = each.value.subnet_id
  tags = {
    Name = "${each.value.instance_name}"
  }
}

output "instances" {
  value       = aws_instance.kubeadm
  description = "All Machine details"
}
