variable "aws_primary_region" {
  description = "Primary region for the AWS resources"
  default     = "eu-west-1" 
}

variable "vm_config" {
  description = "Lists instance objects"
  default = [{}]
}

variable "sg_config" {
  description = "Lists security groups"
    default = [{}]
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  default     = "10.0.0.0/16"
}

variable "r_igw_cidr" {
  description = "CIDR block for IGW route"
  default     = "0.0.0.0/0"
}
variable "public_cidr" {
  description = "CIDR block for Public subnet"
  default     = "10.0.1.0/24"
}

variable "public_az" {
  description = "Availability zone for Public subnet"
  default     = "eu-west-1a"
}

variable "private_cidr" {
  description = "CIDR block for Private subnet"
  default     = "10.0.2.0/24"
}

variable "private_az" {
  description = "Availability zone for Private subnet"
  default     = "eu-west-1b"
}

variable "master_ingress_port" {
  description = "Ingress port for master_security_group"
  default     = 22
}

variable "master_ingress_protocol" {
  description = "Ingress protocol for master_security_group"
  default     = "tcp"
}

variable "master_ingress_cidr" {
  description = "Ingress CIDR block for master_security_group"
  default     = "0.0.0.0/0"
}

variable "master_egress_port" {
  description = "Egress port for master_security_group"
  default     = 0
}

variable "master_egress_protocol" {
  description = "Egress protocol for master_security_group"
  default     = "-1"
}

variable "master_egress_cidr" {
  description = "Egress CIDR block for master_security_group"
  default     = "0.0.0.0/0"
}

variable "worker_ingress_port" {
  description = "Ingress port for worker_security_group"
  default     = 22
}

variable "worker_ingress_protocol" {
  description = "Ingress protocol for worker_security_group"
  default     = "tcp"
}

variable "worker_ingress_cidr" {
  description = "Ingress CIDR block for worker_security_group"
  default     = "0.0.0.0/0"
}

variable "worker_egress_port" {
  description = "Egress port for worker_security_group"
  default     = 0
}

variable "worker_egress_protocol" {
  description = "Egress protocol for worker_security_group"
  default     = "-1"
}

variable "worker_egress_cidr" {
  description = "Egress CIDR block for worker_security_group"
  default     = "0.0.0.0/0"
}

variable "key_name" {
  description = "Key pair name"
}
