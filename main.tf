provider "aws" {
  region = "eu-west-1"
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
  vpc_security_group_ids = each.value.security_groups
  key_name               = "<name-of-your-secret-key>"
  subnet_id              = each.value.subnet_id
  tags = {
    Name = "${each.value.instance_name}"
  }
}

output "instances" {
  value       = aws_instance.kubeadm
  description = "All Machine details"
}
