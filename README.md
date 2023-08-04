# k8s-ec2-terraform
Kubernetes cluster deployment on EC2 using Terraform and kubeadm based on [Benson Philemon's post on Medium](https://medium.com/@benson.philemon/effortlessly-deploy-a-kubernetes-cluster-on-aws-ec2-with-terraform-and-kubeadm-7bb2aae1d5de).

[KISS principle](https://en.wikipedia.org/wiki/KISS_principle), baby!

## Preface and requirements

As commented on [Benson's post](https://medium.com/@benson.philemon/effortlessly-deploy-a-kubernetes-cluster-on-aws-ec2-with-terraform-and-kubeadm-7bb2aae1d5de), this tutorial uses CRI-O as default Container Runtime Interface, and Calico as Container Network Interface.

To provision:
- Three EC2 instances: 
  - one as master node (with 4GB of memory and 2 CPUs); and 
  - two others as workers (with 1GB of memory and 1 CPU each).
- Two security groups, to work as firewalls for inbound traffic on both node types (that is, one SG for master and another for all worker nodes)
- Two subnets, in different availability zones, for each node type to be properly housed;


## 1. Terraform

In a nutshell, this code declaration will create many EC2 instances based on information obtained from the environment variable `vm_config`:

```
#variables.tf
variable "vm_config" {
      description = "List instance objects"
      default = [{}]
    }
```

This information is represented as an array with two items (one for each node type), each containing all of its instance specs. 

> [!WARNING]
> Such information is disclosed here for learning, but remember: not a safe practice.

```
#terraform.tfvars
vm_config = [
  {
    "node_name" : "Master",
    "ami" : "ami-0aa2b7722dc1b5612",
    "no_of_instances" : "1",
    "instance_type" : "t2.medium",
    "subnet_id" : aws_subnet.master_subnet.id,
    "vpc_security_group_ids" : [aws_security_group.master_security_group.id]
  },
  {
    "node_name" : "Worker",
    "ami" : "ami-0aa2b7722dc1b5612",
    "instance_type" : "t2.micro",
    "no_of_instances" : "2"
    "subnet_id" : aws_subnet.worker_subnet.id
    "vpc_security_group_ids" : [aws_security_group.worker_security_group.id]
  }
 ]
```

> [!NOTE]
> `node_name` must define the node types. `Master` has 1 `no_of_instances`, while `Worker` has 2. The rest is a bit obvious.

### main.tf

The code structure is under `main.tf`. Some explanation on the blocks declared:

- `locals`: as the name says, this block [defines local variables to make coding simpler](https://developer.hashicorp.com/terraform/language/values/locals). Two `locals` blocks are declared:
  1. `serverconfig` iterates over `vm_config` and, for each item (`srv`) on the array, it creates a new object (that is, an EC2 instance) based on properties therein defined;
  2. `instances` uses [flatten](https://developer.hashicorp.com/terraform/language/functions/flatten) to convert the elements of `serverconfig` to a flattened list.
```
#main.tf
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
```

- `resource`: basic Terraform block to provision a [resource](https://developer.hashicorp.com/terraform/language/resources/syntax) (in this case, an `aws_instance` named `kubeadm`). There are specific `resource` blocks for instances, VPCs, subnets and security groups.
  - `for_each` has the iteration declaration to provision an instance for each item declared on `instances`;
```
#main.tf
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
```

- `output`: declaration to [return provisioning information on the output line](https://developer.hashicorp.com/terraform/language/values/outputs).
```
#main.tf
output "instances" {
  value       = aws_instance.kubeadm
  description = "All Machine details"
}
```