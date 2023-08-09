# k8s-ec2-terraform

Kubernetes cluster deployment on EC2 using Terraform, Ansible and kubeadm based on [Benson Philemon's post on Medium](https://medium.com/@benson.philemon/effortlessly-deploy-a-kubernetes-cluster-on-aws-ec2-with-terraform-and-kubeadm-7bb2aae1d5de).

[KISS principle](https://en.wikipedia.org/wiki/KISS_principle), baby!

## Preface and requirements

As commented on [Benson's post](https://medium.com/@benson.philemon/effortlessly-deploy-a-kubernetes-cluster-on-aws-ec2-with-terraform-and-kubeadm-7bb2aae1d5de), this tutorial uses CRI-O as default Container Runtime Interface, but I'm not using Calico as Container Network Interface.

The core provisioning requires:
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
- Two subnets, in different availability zones, for each node type to be properly placed;
- One Internet Gateway, for accessing the instances;
- A route for the default Route Table to the Internet Gateway;
- A key pair, to properly SSH into instances;
- A VPC, where all of the above is housed.

### Terminal requirements

- Ansible;
- Terraform;
- AWS CLI (for maintenance on instance level);
- kubectl (for maintenance on container level)

## Infrastructure as Code declaration

```
root/
├── main.tf
├── variables.tf
├── outputs.tf
├── terraform.tfvars # hidden file
└── instance_provisioning/
    ├── ansible_execution.tf
    ├── variables.tf
    ├── ansible-kubernetes-setup.yml
```

The `main.tf` Terraform code on root will be responsible for creating the three instances, each within its matching subnet. Security groups rules will be evenly applied to prevent unrequired ingress access.

Under the `instance_provisioning` directory, the `ansible_execution.tf` child module gets values from `main.tf`'s output and runs the `ansible-kubernetes-setup.yml` Ansible playbook using `local_exec`. This is where Kubernetes and CRI-O are installed.

### variables.tf

Notably, the `vm_config` and `sg_config` environment variables are represented as an arrays; one has all instance requirements, while the latter has all security group rules.

```
#variables.tf

variable "vm_config" {
  description = "List instance objects"
  default = [{}]
}

variable "sg_config" {
  description = "List security groups"
    default = [{}]
}
```


> [!WARNING]
> All `.tfvars` information here declared are for learning purposes only. Disclosing its content is not a safe practice. This file is not included for security reasons.

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

### main.tf

After the declaration of providers on first lines, the key pair definitions are set. 

Resource `tls_private_key.access-maintenance-key` generates a ED25519 algorithm key, while `aws_key_pair.access-maintenance-key` creates a SSH key pair using the key previously created and associates it to an AWS EC2 key pair.
- The requested `key_name` is obtained from the `var.key_name` variable. Storing as variable allows to refer to this key using its name, in the future;
- The `public_key` is obtained from `tls_private_key.access-maintenance-key.public_key_openssh`;
- `provisioner "local-exec"`: After creating the key pair, an additional action will be executed from the terminal:
  - `command = echo...`: This command creates a file titled as the key name (extracted from `var.key_name`) and injects the generated private file on it from `tls_private_key.access-maintenance-key.private_key_pem`. Then, the key's permissions are adjusted to read-only by the terminal.

```
#main.tf

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
```
Creation of network features is very straightforward. Make sure everyhing connects to everything.

```
#main.tf

resource "aws_vpc" "cluster_vpc" {
  cidr_block = var.vpc_cidr_block
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.cluster_vpc.id
}

resource "aws_route" "r" {
  route_table_id            = aws_vpc.cluster_vpc.default_route_table_id
  destination_cidr_block    = var.r_cidr_block
  gateway_id                = aws_internet_gateway.igw.id
  depends_on                = [aws_vpc.cluster_vpc]
}

resource "aws_subnet" "master_subnet" {
  vpc_id                  = aws_vpc.cluster_vpc.id
  cidr_block              = var.master_subnet_cidr
  availability_zone       = var.master_subnet_az
  tags = {
    Name = "Master"
  }
}

resource "aws_subnet" "worker_subnet" {
  vpc_id                  = aws_vpc.cluster_vpc.id
  cidr_block              = var.worker_subnet_cidr
  availability_zone       = var.worker_subnet_az
  tags = {
    Name = "Worker"
  }
}
```

Security group provisioning is set dynamically, as it iterates through the `sg_config` environment variable and defines rules based on that list.

```
#main.tf

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
```

Elastic IPs are provisioned for providing public IPs to our instances. That will allow SSH to be used, that is, Ansible will depend on this to work. Both creation and association to instances are based on iteration.

```
#main.tf

resource "aws_eip" "instance_eips" {
  for_each = local.instance_ids
  instance = local.instance_ids[each.key]
}

resource "aws_eip_association" "instance_eip_associations" {
  for_each = local.instance_ids
  instance_id   = local.instance_ids[each.key]
  allocation_id = aws_eip.instance_eips[each.key].id
}
```

#### Where the magic happens

The `aws_instance.kubeadm` is the declaration that provisions our instances. It `depends_on` all other network resources to be provisioned.
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
```

`locals`: as the name says, this block [defines local variables to make coding simpler](https://developer.hashicorp.com/terraform/language/values/locals). The environment variables defined here are applicable everywhere, not only on the block where it was provisioned.

This is actually the logic that fetches information and prepares it for `aws_instance.kubeadm`.

  1. `serverconfig` iterates over `vm_config` and, for each item (`srv`) on the array, it creates a new object (that is, an EC2 instance) based on properties therein defined;
  2. `instances` uses [flatten](https://developer.hashicorp.com/terraform/language/functions/flatten) to convert the elements of `serverconfig` to a flattened list.
  3. `instance_ids` gets the ID from each provisioned instance, for outputting reasons.

```
#main.tf

locals {
  serverconfig = [ # Fetches instances from .tfvars file
    for srv in var.vm_config : [
      for i in range(1, srv.no_of_instances+1) : {
        instance_name   = "${srv.node_name}-${i}"
        instance_type   = srv.instance_type
        ami             = srv.ami
      }
    ]
  ]
  instances = flatten(local.serverconfig) # Flattening
  instance_ids = { # Gets ID from each instance provisioned
    for i in local.instances : i.instance_name => aws_instance.kubeadm[i.instance_name].id
  }
}
```

## Execution

After setting everything up to this point, just run `terraform apply` to see the magic happening. Once completed, run the following code to check the results on the output:

```
aws ec2 describe-instances \
    --filters Name=tag-key,Values=Name \
    --query 'Reservations[*].Instances[*].{SubnetID:SubnetId,VPC:VpcId,Instance:InstanceId,AZ:Placement.AvailabilityZone,Name:Tags[?Key==`Name`]|[0].Value}' \ 
    --output table
```

Results will be displayed like this:

```
--------------------------------------------------------------------------------------------------------
|                                           DescribeInstances                                          |
+------------+----------------------+-----------+----------------------------+-------------------------+
|     AZ     |      Instance        |   Name    |         SubnetID           |           VPC           |
+------------+----------------------+-----------+----------------------------+-------------------------+
|  eu-west-1a|  i-0ddd44f8e3132d25a |  Master-1 |  subnet-01e721705253880b6  |  vpc-027af063534c396b1  |
|  eu-west-1b|  i-0f9d5665f8ef8f398 |  Worker-1 |  subnet-096096aec10438580  |  vpc-027af063534c396b1  |
|  eu-west-1b|  i-0fd51de0a3b30a6bb |  Worker-2 |  subnet-096096aec10438580  |  vpc-027af063534c396b1  |
+------------+----------------------+-----------+----------------------------+-------------------------+
```