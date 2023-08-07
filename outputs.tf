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