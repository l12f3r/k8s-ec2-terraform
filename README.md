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

## 1. Terraform

The Terraform declaration must specify all the aforementioned infrastructure required. Code will be set for the two node types (Master and Worker).

Different from other Terraform projects I worked on, this one "stores" arrays with instance specs on an environment variable (`vm_config`), contained on the `.tfvars` file. Such information is disclosed here for learning, but remember: not a safe practice.

```
#terraform.tfvars
vm_config = [
  {
    "node_name" : "Master",
    "ami" : "ami-0aa2b7722dc1b5612",
    "no_of_instances" : "1",
    "instance_type" : "t2.medium",
    "subnet_id" : "subnet-780bde35",
    "vpc_security_group_ids" : ["sg-053564b3ef25f1f05"]
  },
  {
    "node_name" : "Worker",
    "ami" : "ami-0aa2b7722dc1b5612",
    "instance_type" : "t2.micro",
    "no_of_instances" : "2"
    "subnet_id" : "subnet-780bde35"
    "vpc_security_group_ids" : ["sg-0e037e6dd7973a887"]
  }
 ]

```
### Worth noting:
`node_name` must define the node types. `Master` has 1 `no_of_instances`, while `Worker` has 2.
