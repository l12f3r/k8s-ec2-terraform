provider "aws" {
  region = "eu-west-1"
}

resource "tls_private_key" "access-key" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "access-key" {
  key_name   = var.key_name
  public_key = tls_private_key.access-key.public_key_openssh
  provisioner "local-exec" { 
    command = "echo '${tls_private_key.access-key.private_key_pem}' > ./${var.key_name} | chmod 400 ./${var.key_name}"
  }
}

resource "aws_vpc" "cluster_vpc" {
  cidr_block = var.vpc_cidr
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.cluster_vpc.id
}

resource "aws_route" "r" {
  route_table_id         = aws_vpc.cluster_vpc.default_route_table_id
  destination_cidr_block = var.r_cidr
  gateway_id             = aws_internet_gateway.igw.id
  local_gateway_id       = aws_vpc.cluster_vpc.id
  depends_on             = [aws_vpc.cluster_vpc]
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.cluster_vpc.id
  cidr_block        = var.public_cidr
  availability_zone = var.public_az
  tags = {
    Name = "Public"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.cluster_vpc.id
  cidr_block        = var.private_cidr
  availability_zone = var.private_az
  tags = {
    Name = "Private"
  }
}

resource "aws_security_group" "master_security_group" {
  name_prefix = "Master-SG-"
  vpc_id      = aws_vpc.cluster_vpc.id
  dynamic "ingress" {
    for_each = var.sg_config[0].master.ingress_ports    
    content {
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }
  }
  dynamic "egress" {
    for_each = var.sg_config[0].master.egress_ports
    content {
      from_port   = egress.value.from_port
      to_port     = egress.value.to_port
      protocol    = egress.value.protocol
      cidr_blocks = egress.value.cidr_blocks
    }
  }
}  

resource "aws_security_group" "worker_security_group" {
  name_prefix = "Worker-SG-"
  vpc_id      = aws_vpc.cluster_vpc.id
  dynamic "ingress" {
    for_each = var.sg_config[1].worker.ingress_ports
    content {
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }
  }

  dynamic "egress" {
    for_each = var.sg_config[1].worker.egress_ports
    content {
      from_port   = egress.value.from_port
      to_port     = egress.value.to_port
      protocol    = egress.value.protocol
      cidr_blocks = egress.value.cidr_blocks
    }
  }
}
resource "aws_eip" "maintenance" {
  instance   = aws_instance.maintenance.id
  depends_on = [aws_internet_gateway.igw]
}

resource "aws_eip_association" "maintenance" {
  instance_id   = aws_instance.maintenance.id
  allocation_id = aws_eip.maintenance.id
  depends_on    = [aws_eip.maintenance]
}

resource "aws_instance" "kubeadm" {
  for_each               = {for server in local.instances: server.instance_name => server}
  ami                    = each.value.ami
  instance_type          = each.value.instance_type
  key_name               = var.key_name
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = toset([each.value.instance_type == "t2.medium" ? aws_security_group.master_security_group.id : aws_security_group.worker_security_group.id]) # TODO: find alternative to condition on hardcoded
  depends_on = [ 
    aws_internet_gateway.igw,
    aws_security_group.master_security_group,
    aws_security_group.worker_security_group,
    aws_subnet.public,
    aws_subnet.private,
  ]
  tags = {
    Name = "${each.value.instance_name}"
  }
}

locals {
  serverconfig = [
    for srv in var.vm_config : [
      for i in range(1, srv.no_of_instances+1) : {
        instance_name   = "${srv.node_name}-${i}"
        instance_type   = srv.instance_type
        ami             = srv.ami
      }
    ]
  ]
  instances = flatten(local.serverconfig) 
  instance_ips = {
    for i in local.instances : i.instance_name => aws_instance.kubeadm[i.instance_name].private_ip
  }
}

resource "aws_instance" "maintenance" {
  ami                    = local.instances[0].ami
  instance_type          = local.instances[0].instance_type
  key_name               = var.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.master_security_group.id]
  depends_on = [ 
    aws_instance.kubeadm
  ]
  provisioner "local-exec" {
    command = "ANSIBLE_PRIVATE_KEY_FILE=${var.key_name}.pem ansible-playbook -i '${join(",", values(local.instance_ips))}' ansible-kubernetes-setup.yml"
    interpreter = ["bash", "-c"]
  }
  tags = {
    Name = "Maintenance"
  }
}