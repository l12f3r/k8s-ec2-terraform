module "instance_provisioning" {
  source = "./instance_provisioning"
  output_id = module.root.output_all_ids
  output_ip = module.root.output_all_ips
}

resource "null_resource" "run_ansible" {
  for_each = toset(output_id)
  depends_on = [ module.root.output_all_ips]
  provisioner "local-exec" {
    command     = "ANSIBLE_PRIVATE_KEY_FILE=${output_key_name}.pem | ansible-playbook -i '${self.output_ip},' ansible-kubernetes-setup.yml"
    interpreter = ["bash", "-c"]
  }
}