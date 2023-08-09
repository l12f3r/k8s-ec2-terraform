module "instance_provisioning" {
  source = "./instance_provisioning"
  # output_id = module.root.output_all_ids
  # output_ip = module.root.output_all_ips
}

resource "null_resource" "run_ansible" {
  for_each = toset(var.output_all_ids)
  triggers = {
    instance_id = var.output_all_ids[each.key]
  }
  provisioner "local-exec" {
    command     = "ANSIBLE_PRIVATE_KEY_FILE=${var.output_key_name}.pem | ansible-playbook -i '${var.output_all_ips[each.key]},' ansible-kubernetes-setup.yml"
    interpreter = ["bash", "-c"]
    log         = {
      level = "debug"
    }
  }
}