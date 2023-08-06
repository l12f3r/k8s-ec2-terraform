variable "vm_config" {
  description = "List instance objects"
  default = [{}]
}

variable "sg_config" {
  description = "List security groups"
    default = [{}]
}

variable "vpc_cidr_block" {
  description = "CIDR block for VPC"
  default     = "10.0.0.0/16"
}

variable "master_subnet_cidr" {
  description = "CIDR block for Master subnet"
  default     = "10.0.1.0/24"
}

variable "master_subnet_az" {
  description = "Availability zone for Master subnet"
  default     = "eu-west-1a"
}

variable "worker_subnet_cidr" {
  description = "CIDR block for Worker subnet"
  default     = "10.0.2.0/24"
}

variable "worker_subnet_az" {
  description = "Availability zone for Worker subnet"
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