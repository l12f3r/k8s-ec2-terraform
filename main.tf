provider "aws" {
  region = "eu-west-1"
}

resource "tls_private_key" "access-maintenance-key" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "access-maintenance-key" {
  key_name   = var.key_name
  public_key = tls_private_key.access-maintenance-key.public_key_openssh
  provisioner "local-exec" { 
    command = "echo '${tls_private_key.access-maintenance-key.private_key_pem}' > ./${var.key_name} | chmod 400 ./${var.key_name}"
  }
}

resource "aws_vpc" "cluster_vpc" {
  cidr_block = var.vpc_cidr_block
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.cluster_vpc.id
}

resource "aws_route" "r" {
  route_table_id         = aws_vpc.cluster_vpc.default_route_table_id
  destination_cidr_block = var.r_cidr_block
  gateway_id             = aws_internet_gateway.igw.id
  depends_on             = [aws_vpc.cluster_vpc]
}

resource "aws_subnet" "master_subnet" {
  vpc_id            = aws_vpc.cluster_vpc.id
  cidr_block        = var.master_subnet_cidr
  availability_zone = var.master_subnet_az
  tags = {
    Name = "Master"
  }
}

resource "aws_subnet" "worker_subnet" {
  vpc_id            = aws_vpc.cluster_vpc.id
  cidr_block        = var.worker_subnet_cidr
  availability_zone = var.worker_subnet_az
  tags = {
    Name = "Worker"
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

resource "aws_eip" "instance_eips" {
  for_each   = local.instance_ids
  instance   = local.instance_ids[each.key]
  depends_on = [aws_internet_gateway.igw]
}

resource "aws_eip_association" "instance_eip_associations" {
  for_each      = local.instance_ids
  instance_id   = local.instance_ids[each.key]
  allocation_id = aws_eip.instance_eips[each.key].id
  depends_on = [aws_eip.instance_eips]
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
  subnet_id              = each.value.instance_type == "t2.medium" ? aws_subnet.master_subnet.id : aws_subnet.worker_subnet.id # TODO: find alternative to condition on hardcoded
  vpc_security_group_ids = toset([each.value.instance_type == "t2.medium" ? aws_security_group.master_security_group.id : aws_security_group.worker_security_group.id]) # TODO: find alternative to condition on hardcoded
  depends_on = [ 
    aws_internet_gateway.igw,
    aws_security_group.master_security_group,
    aws_security_group.worker_security_group,
    aws_subnet.master_subnet,
    aws_subnet.worker_subnet,
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
  instance_ids = { 
    for i in local.instances : i.instance_name => aws_instance.kubeadm[i.instance_name].id
  }
  instance_ips = {
    for i in local.instances : i.instance_name => aws_instance.kubeadm[i.instance_name].private_ip
  }
}

output "output_all_ids" {
  value = [for i, _ in local.instance_ids : aws_instance.kubeadm[i].id]
}

output "output_all_ips" {
  value = [for i, _ in local.instance_ids : aws_instance.kubeadm[i].private_ip]
}

output "output_key_name" {
  value = var.key_name
  sensitive = true
}

resource "aws_instance" "maintenance" {
  ami                    = local.instances[0].ami
  instance_type          = local.instances[0].instance_type
  key_name               = var.key_name
  subnet_id              = aws_subnet.master_subnet.id
  vpc_security_group_ids = [aws_security_group.master_security_group.id]
  depends_on = [ 
    aws_instance.kubeadm
  ]
  # provisioner "remote-exec" {
  #   inline     = ["ANSIBLE_PRIVATE_KEY_FILE=${var.key_name}.pem | ansible-playbook -i '${local.instance_ids[*].private_ip},' ansible-kubernetes-setup.yml"]
  # }

  # provisioner "local-exec" {
  #   command     = "ANSIBLE_PRIVATE_KEY_FILE=${var.key_name}.pem | ansible-playbook -i '${instance_ips}' ansible-kubernetes-setup.yml"
  #   interpreter = ["bash", "-c"]
  # }
  provisioner "local-exec" {
    command = "ANSIBLE_PRIVATE_KEY_FILE=${var.key_name}.pem ansible-playbook -i '${join(",", values(local.instance_ips))}' ansible-kubernetes-setup.yml"
    interpreter = ["bash", "-c"]
  }
  tags = {
    Name = "Instance used for maintenance"
  }
}

# resource "null_resource" "ansible_provisioning" {
#   triggers = {
#   maintenance_ip = aws_instance.maintenance.private_ip
#   }
#
#   provisioner "local-exec" {
#     command = "ANSIBLE_PRIVATE_KEY_FILE=${var.key_name}.pem ansible-playbook -i '${join(",", values(local.instance_ips))}' ansible-kubernetes-setup.yml"
#     interpreter = ["bash", "-c"]
#   }
#
#   depends_on = [aws_instance.maintenance, aws_instance.kubeadm]
# }