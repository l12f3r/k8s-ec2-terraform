# k8s-ec2-terraform
Kubernetes cluster deployment on EC2 using Terraform and kubeadm based on [Benson Philemon's post on Medium](https://medium.com/@benson.philemon/effortlessly-deploy-a-kubernetes-cluster-on-aws-ec2-with-terraform-and-kubeadm-7bb2aae1d5de).

[KISS principle](https://en.wikipedia.org/wiki/KISS_principle), baby!

## Preface and requirements

As commented on [Benson's post](https://medium.com/@benson.philemon/effortlessly-deploy-a-kubernetes-cluster-on-aws-ec2-with-terraform-and-kubeadm-7bb2aae1d5de), this tutorial uses CRI-O as default Container Runtime Interface, but I'm not using Calico as Container Network Interface.

To provision:
- Three EC2 instances: 
  - one as master node (with 4GB of memory and 2 CPUs); and 
  - two others as workers (with 1GB of memory and 1 CPU each).
- Two security groups, to work as firewalls for inbound traffic on both node types:
  - the master node security group needs to have the following ports opened:
    - TCP 6443 → For Kubernetes API server
    - TCP 2379–2380 → For etcd server client API
    - TCP 10250 → For Kubelet API
    - TCP 10259 → For kube-scheduler
    - TCP 10257 → For kube-controller-manager
    - TCP 22 → For remote access with SSH 
  - the following ports must be opened for the worker node:
    - TCP 10250 → For Kubelet API
    - TCP 30000–32767 → NodePort Services
    - TCP 22 → For remote access with SSH
- Two subnets, in different availability zones, for each node type to be properly housed.

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
> All `.tfvars` information is disclosed here for learning, but remember: not a safe practice.

```
#terraform.tfvars
vm_config = [
  {
    "node_name" : "Master",
    "ami" : "ami-0aa2b7722dc1b5612",
    "instance_type" : "t2.medium",
    "no_of_instances" : "1",
  },
  {
    "node_name" : "Worker",
    "ami" : "ami-0aa2b7722dc1b5612",
    "instance_type" : "t2.micro",
    "no_of_instances" : "2", 
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
        ami             = srv.ami
      }
    ]
  ]
}

locals {
  instances = flatten(local.serverconfig)
}
```

- `resource`: basic Terraform block to provision a [resource](https://developer.hashicorp.com/terraform/language/resources/syntax) (in this case, an `aws_instance` named `kubeadm`). There are specific `resource` blocks for instances, VPCs, subnets and security groups.
  - security group rules are declared as array on the `.tfvars` file as well, under the `sg_config` environment variable:
```
#terraform.tfvars
sg_config = [
  {
    master = {
        ingress_ports = [
            {
                # Kubernetes API server
                from_port = 6443, 
                to_port = 6443, 
                protocol = "tcp", 
                cidr_blocks = ["0.0.0.0/0"]
            },
            {
                # etcd server client API
                from_port = 2379, 
                to_port = 2380, 
                protocol = "tcp", 
                cidr_blocks = ["0.0.0.0/0"]
            },
            {
                # Kubelet API
                from_port = 10250, 
                to_port = 10250, 
                protocol = "tcp", 
                cidr_blocks = ["0.0.0.0/0"]
            },
            {
                # kube-scheduler
                from_port = 10259, 
                to_port = 10259, 
                protocol = "tcp", 
                cidr_blocks = ["0.0.0.0/0"]
            },
            {
                # kube-controller-manager
                from_port = 10257, 
                to_port = 10257, 
                protocol = "tcp", 
                cidr_blocks = ["0.0.0.0/0"]
            },
            {
                # remote access using SSH
                from_port = 22, 
                to_port = 22, 
                protocol = "tcp", 
                cidr_blocks = ["0.0.0.0/0"]
            }
        ],
        egress_ports = [
            {
                from_port = 0, 
                to_port = 0, 
                protocol = "-1", 
                cidr_blocks = ["0.0.0.0/0"]
            }
        ]
    }
  },
  {
    worker = {
        ingress_ports = [
            {
                #Kubelet API
                from_port = 10250, 
                to_port = 10250, 
                protocol = "tcp", 
                cidr_blocks = ["0.0.0.0/0"]
            },
            {
                # NodePort Services
                from_port = 30000, 
                to_port = 32767, 
                protocol = "tcp", 
                cidr_blocks = ["0.0.0.0/0"]
            },
            {
                # remote access using SSH
                from_port = 22, 
                to_port = 22, 
                protocol = "tcp", 
                cidr_blocks = ["0.0.0.0/0"]
            }
        ],
        egress_ports = [
            {
                from_port = 0, 
                to_port = 0, 
                protocol = "-1", 
                cidr_blocks = ["0.0.0.0/0"]
            }
        ]
    }
  }  
]
```
  - `for_each` has the iteration declaration to provision an instance for each item declared on `instances`;
```
#main.tf
resource "aws_instance" "kubeadm" {
  for_each               = {for server in local.instances: server.instance_name => server}
  ami                    = each.value.ami
  instance_type          = each.value.instance_type
  key_name               = var.key_name
  tags = {
    Name = "${each.value.instance_name}"
  }
}
```

> [!NOTE]
> As one may notice, those instances to be provisioned are not attached to the VPC, subnets and security groups declared on code. This occurs due to `.tfvars` files not accepting environment variables - the instance would need to be attached to objects declared on `vm_config`, and those would be provided after apply only.