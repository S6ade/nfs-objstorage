output "vm-ip" {
	value = { for k, v in yandex_compute_instance.serv_config : k => v.network_interface.0.ip_address}
}
output "vm_nat_ip" {
  value = { for k, v in  yandex_compute_instance.serv_config : k => v.network_interface.0.nat_ip_address}
}