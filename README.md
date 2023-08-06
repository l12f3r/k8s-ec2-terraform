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
    "ami" : "ami-061da7f56569c2493",
    "instance_type" : "t2.medium",
    "no_of_instances" : "1",
  },
  {
    "node_name" : "Worker",
    "ami" : "ami-061da7f56569c2493",
    "instance_type" : "t2.micro",
    "no_of_instances" : "2", 
  }
]
```

> [!NOTE]
> `node_name` must define the node types. `Master` has 1 `no_of_instances`, while `Worker` has 2. The rest is a bit obvious.

### main.tf

The code structure is under `main.tf`. Some explanation on the blocks declared:

- `resource`: basic Terraform block to provision [resources](https://developer.hashicorp.com/terraform/language/resources/syntax). There are specific `resource` blocks for instances, VPCs, subnets and security groups. A few notes:
  - `aws_instance.kubeadm` is the declaration that provisions our three instances. It `depends_on` all other resources to be provisioned.
    - `for_each` iterates over the flattened `locals.instances` list and provisions an amount of instances for each item therein included;
    - `subnet_id` is a conditional: if the instance type is `t2.medium` (which occurs to all `Master` nodes, as per `vm_config`), it should be associated to `aws_subnet.master_subnet` by its ID. Otherwise, it associates to `aws_subnet.worker_subnet`;
    - The same conditional is applied to `vpc_security_group_ids`, for associating the right instance to its respective security group, but the `toset()` function was applied to convert values to list, as expected by this property.

```
#main.tf

resource "aws_instance" "kubeadm" {
  for_each               = {for server in local.instances: server.instance_name => server}
  ami                    = each.value.ami
  instance_type          = each.value.instance_type
  key_name               = var.key_name
  subnet_id              = each.value.instance_type == "t2.medium" ? aws_subnet.master_subnet.id : aws_subnet.worker_subnet.id
  vpc_security_group_ids = toset([each.value.instance_type == "t2.medium" ? aws_security_group.master_security_group.id : aws_security_group.worker_security_group.id])
  depends_on = [ 
    aws_security_group.master_security_group,
    aws_security_group.worker_security_group,
    aws_subnet.master_subnet,
    aws_subnet.worker_subnet,
  ]
  tags = {
    Name = "${each.value.instance_name}"
  }
}
```
  
  - Security group rules are declared as array on the `.tfvars` file as well, under the `sg_config` environment variable:

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

- `locals`: as the name says, this block [defines local variables to make coding simpler](https://developer.hashicorp.com/terraform/language/values/locals). This is actually the logic that fetches information and prepares it for `aws_instance.kubeadm`. Two `locals` blocks are declared:
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

After setting everything up to this point, just run `terraform apply` to see the magic happening. Once completed, run the following code to check the results on the output:

```
aws ec2 describe-instances \
    --filters Name=tag-key,Values=Name \
    --query 'Reservations[*].Instances[*].{Subnet:SubnetID,VPC:VpcId,Instance:InstanceId,AZ:Placement.AvailabilityZone,Name:Tags[?Key==`Name`]|[0].Value}' \
    --output table
```