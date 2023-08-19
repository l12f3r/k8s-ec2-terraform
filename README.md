# k8s-ec2-terraform

Kubernetes cluster deployment on EC2 using Terraform, Ansible and kubeadm based on [Benson Philemon's post on Medium](https://medium.com/@benson.philemon/effortlessly-deploy-a-kubernetes-cluster-on-aws-ec2-with-terraform-and-kubeadm-7bb2aae1d5de).

I'm not creating any modules, using outputs or other stuff. [KISS principle](https://en.wikipedia.org/wiki/KISS_principle), baby!

## Preface and requirements

As commented on [Benson's post](https://medium.com/@benson.philemon/effortlessly-deploy-a-kubernetes-cluster-on-aws-ec2-with-terraform-and-kubeadm-7bb2aae1d5de), this tutorial uses CRI-O as default Container Runtime Interface, but I'm not using Calico as Container Network Interface.

The core provisioning requires:
- Four EC2 instances: 
  - one as Master node (with 4GB of memory and 2 CPUs);
  - two others as Workers (with 1GB of memory and 1 CPU each); and
  - one as Maintenance instance.
- Two security groups, to work as firewalls for inbound traffic on Worker and Master nodes:
- Two subnets - a public (for the maintenance instance) and a private, for our instances;
- One Internet Gateway;
- One public Route Table with a route towards the Internet Gateway;
- One local route associated to the default Route Table;
- A key pair, for AWS authentication;
- A VPC, where everything above is housed.

### Terminal requirements

- Ansible;
- Terraform;
- AWS CLI (for maintenance on instance level);
- kubectl (for maintenance on container level)

## Infrastructure as Code declaration

### Overview

```
root/
├── main.tf
├── variables.tf
├── terraform.tfvars              # hidden file
└── ansible-kubernetes-setup.yml  # Ansible provisioning
```

The `main.tf` Terraform code on root will be responsible for creating all instances, each within its matching subnet. Security group rules will be evenly applied to prevent unrequired ingress access.

It also uses the maintenance instance to run the `ansible-kubernetes-setup.yml` Ansible playbook using `local_exec`. This is where Kubernetes and CRI-O are installed.

Notably, the `vm_config` and `sg_config` environment variables are represented as arrays; one has all instance requirements, while the latter has all security group rules.

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
> All mock `.tfvars` information here declared are for learning purposes only. Disclosing its content is not a safe practice. This file is not included on Git for security reasons, and I highly encourage you to provide your own data sources upon using this code.

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
                cidr_blocks = ["10.0.0.0/16"]  #from local instances only
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
                cidr_blocks = ["10.0.0.0/16"]  #from local instances only
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

### 1. Key management

After the declaration of providers on first lines, the key pair definitions are set. 

Resource `tls_private_key.access-key` generates a ED25519 algorithm key, while `aws_key_pair.access-key` creates a SSH key pair using the key previously created and associates it to an AWS EC2 key pair.
- The requested `key_name` is obtained from the `var.key_name` variable. Storing as variable allows to refer to this key using its name, in the future;
- The `public_key` is obtained from `tls_private_key.access-key.public_key_openssh`;
- `provisioner "local-exec"`: After creating the key pair, an additional action will be executed from the terminal:
  - `command = echo...`: This command creates a file titled as the key name (extracted from `var.key_name`) and injects the generated private file on it from `tls_private_key.access-key.private_key_pem`. Then, the key's permissions are adjusted to read-only by the terminal.

```
#main.tf

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
```

### 2. Networking

The network layout, on a rough overview, should be something like this:

```
aws_vpc.cluster_vpc
└─aws_subnet.public                 # Public subnet
  └─aws_route.igw                   # Route to the Internet Gateway
    └─aws_internet_gateway.igw      # Internet Gateway 🌎
└─aws_subnet.private                # Private subnet
```

Code declaration for network features is very straightforward: 
- The public subnet is explicitly associated to the public route table, which has a route to the Internet Gateway (apart from default local route);
- The private subnet is explicitly associated to the default route table, which only has the default local route.

Make sure everyhing connects to everything.

```
#main.tf

resource "aws_vpc" "cluster_vpc" {
  cidr_block = var.vpc_cidr
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.cluster_vpc.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.cluster_vpc.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_vpc.cluster_vpc.default_route_table_id
}

resource "aws_route" "igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = var.r_igw_cidr
  gateway_id             = aws_internet_gateway.igw.id
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
```

### 3. Instances

#### Security groups

The Maintenance instance has its own security group, with its specifications:

```
#main.tf

resource "aws_security_group" "maintenance" {
  name_prefix = "Maintenance-SG-"
  vpc_id      = aws_vpc.cluster_vpc.id

  # Ingress rule for SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Should be changed to a more restricted IP range
  }

 # Ingress rule for communication with instances in private subnet
  ingress {
    from_port       = 0
    to_port         = 65535  # Allow all ports for communication
    protocol        = "tcp"
    security_groups = [aws_security_group.worker.id, aws_security_group.master.id]
  }

  # Ingress rule for mirror requests
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Should be changed to a more restricted IP range
  }

  # Egress rule
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

```

For Kubernetes instances, the security group provisioning is set dynamically, as it iterates through the `sg_config` environment variable on the `variables.tf` file and defines rules based on that list.

Required ports for Master node:
- TCP 6443      → For Kubernetes API server
- TCP 2379–2380 → For etcd server client API
- TCP 10250     → For Kubelet API
- TCP 10259     → For kube-scheduler
- TCP 10257     → For kube-controller-manager
- TCP 22        → For SSH access (Ansible provisioning)

And for the Worker node:
- TCP 10250       → For Kubelet API
- TCP 30000–32767 → NodePort Services
- TCP 22          → For SSH access (Ansible provisioning)

```
#main.tf

resource "aws_security_group" "master" {
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

resource "aws_security_group" "worker" {
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

#### Elastic IP

An Elastic IP is provisioned for providing a public IP to the maintenance instance. It requires an `aws_eip_association` resource, that will the link between the instance and the EIP.

```
#main.tf

resource "aws_eip" "maintenance" {
  instance   = aws_instance.maintenance.id
  depends_on = [aws_instance.kubeadm]
}

resource "aws_eip_association" "maintenance" {
  instance_id   = aws_instance.maintenance.id
  allocation_id = aws_eip.maintenance.id
  depends_on    = [aws_eip.maintenance]
}
```

#### Instance declaration

The `aws_instance.kubeadm` resource is the declaration that provisions our Kubernetes instances. It `depends_on` all other network resources to be provisioned.
  - `for_each` iterates over the flattened `locals.instances` list and provisions an amount of instances for each item therein included;
  - `vpc_security_group_ids`, associates the right instance to its respective security group - the `toset()` function was applied to convert values to list, as expected by this property.

```
#main.tf

resource "aws_instance" "kubeadm" {
  for_each               = {for server in local.instances: server.instance_name => server}
  ami                    = each.value.ami
  instance_type          = each.value.instance_type
  key_name               = var.key_name
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = toset([each.value.instance_type == "t2.medium" ? aws_security_group.master.id : aws_security_group.worker.id]) # TODO: find alternative to condition on hardcoded
  depends_on = [ 
    aws_internet_gateway.igw,
    aws_security_group.master,
    aws_security_group.worker,
    aws_subnet.public,
    aws_subnet.private,
  ]
  tags = {
    Name = "${each.value.instance_name}"
  }
}
```

The `aws_instance.maintenance` resource is the declaration for our Maintenance instance. It is responsible for load balancing, provisioning all others instances and working as update mirror.

```
#main.tf

resource "aws_instance" "maintenance" {
  ami                      = local.instances[0].ami
  instance_type            = local.instances[0].instance_type
  key_name                 = var.key_name
  subnet_id                = aws_subnet.public.id
    vpc_security_group_ids = [aws_security_group.maintenance.id]
 
  tags = {
    Name = "Maintenance"
  }
}
```

#### Local variables

`locals`: as the name says, this block [defines local variables to make coding simpler](https://developer.hashicorp.com/terraform/language/values/locals). The environment variables defined here are applicable everywhere, not only on the block where it was provisioned.

This is actually the logic that fetches information and prepares it for `aws_instance.kubeadm`.

  1. `serverconfig` iterates over `vm_config` and, for each item (`srv`) on the array, it creates a new object (that is, an EC2 instance) based on properties therein defined;
  2. `instances` uses [flatten](https://developer.hashicorp.com/terraform/language/functions/flatten) to convert the elements of `serverconfig` to a flattened list.
  3. `instance_ips` fetches the private IP from each provisioned instance, so it can be used by the Ansible command on Maintenance.

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
  instances = flatten(local.serverconfig) 
  instance_ips = {
    for i in local.instances : i.instance_name => aws_instance.kubeadm[i.instance_name].private_ip
  }
}
```

#### Instance provisioning

As mentioned on the `local-exec` declaration, this file (or playbook, according to Ansible jargon) contains code for configuring each instance properly.

- **Install packages**: all Kubernetes-related packages and CRI-O, apart from other packages to ensure a safe and transparent cryptographic communication on the cluster, are installed in this task.

```
# ansible-kubernetes-setup.yml

---
- hosts: all
  become: true
  tasks:
    - name: Install Kubernetes-related packages
      apt:
        name: ['apt-transport-https', 'ca-certificates', 'curl', 'software-properties-common', 'cri-o', 'kubeadm', 'kubelet', 'kubectl']
        update_cache: yes

```
- All kernel modules and sysctl parameters to use Kubernetes (and CRI-O) are defined and loaded on the following tasks:

```
# ansible-kubernetes-setup.yml

    - name: Copy kernel modules file (/etc/modules-load.d/k8s.conf)
      copy:
        content: |
          overlay
          br_netfilter
        dest: /etc/modules-load.d/k8s.conf
        owner: root
        group: root
        mode: '0644'

    - name: Load kernel modules
      command: "{{ item }}"
      with_items:
        - modprobe overlay
        - modprobe br_netfilter

    - name: Copy sysctl parameters (/etc/sysctl.d/k8s.conf)
      copy:
        content: |
          net.bridge.bridge-nf-call-iptables  = 1
          net.bridge.bridge-nf-call-ip6tables = 1
          net.ipv4.ip_forward                 = 1
        dest: /etc/sysctl.d/k8s.conf
        owner: root
        group: root
        mode: '0644'

    - name: Load sysctl parameters
      sysctl:
        name:
          - net.bridge.bridge-nf-call-iptables
          - net.bridge.bridge-nf-call-ip6tables
          - net.ipv4.ip_forward
        value: 1
        sysctl_set: yes
        state: present

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
-----------------------------------------------------------------------------------------------------------
|                                            DescribeInstances                                            |
+------------+----------------------+--------------+----------------------------+-------------------------+
|     AZ     |      Instance        |    Name      |         SubnetID           |           VPC           |
+------------+----------------------+--------------+----------------------------+-------------------------+
|  eu-west-1b|  i-00032b8c606ac7698 |  Master-1    |  subnet-0fd054f9dfdcbc8b4  |  vpc-00b57416dae17c7e2  |
|  eu-west-1b|  i-0d52399007348ed8f |  Worker-1    |  subnet-0fd054f9dfdcbc8b4  |  vpc-00b57416dae17c7e2  |
|  eu-west-1b|  i-0d81c918170b609e6 |  Worker-2    |  subnet-0fd054f9dfdcbc8b4  |  vpc-00b57416dae17c7e2  |
|  eu-west-1a|  i-0a7a9610644274c54 |  Maintenance |  subnet-0c6c44712a38a8f2e  |  vpc-00b57416dae17c7e2  |
+------------+----------------------+--------------+----------------------------+-------------------------+
```