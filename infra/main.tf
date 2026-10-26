resource "yandex_compute_disk" "boot_disk" {
    for_each = var.serv_configs
    name = "boot-${each.key}"
    type = "network-hdd"
    zone = "ru-central1-d"
    size = each.value["disk"]
    image_id = each.value["template"]
}

resource "yandex_vpc_network" "network-vm" {
	name = "network-vm"
}

resource "yandex_vpc_subnet" "subnet-vm" {
	name = "subnet-vm"
	zone = "ru-central1-d"
	network_id = yandex_vpc_network.network-vm.id
	v4_cidr_blocks = ["192.168.10.0/24"]
}

resource "yandex_compute_instance" "serv_config" {
	for_each = var.serv_configs
	name = "vm-${each.key}"

	platform_id = "standard-v2"

	depends_on = [yandex_compute_disk.boot_disk]

	resources {
	  cores = each.value["vm_cpu"]
	  memory = each.value["ram"]
	  core_fraction = 20
	}

	boot_disk {
	   disk_id = yandex_compute_disk.boot_disk[each.key].id
	}

	network_interface {
	  subnet_id = yandex_vpc_subnet.subnet-vm.id
	  nat = true
	  security_group_ids = [yandex_vpc_security_group.sg_vm.id]
	}
	  metadata = {
    user-data = <<-EOT
      #cloud-config
      users:
        - name: s6ade
          sudo: ALL=(ALL) NOPASSWD:ALL
          shell: /bin/bash
          ssh_authorized_keys:
            - ${var.ssh_public_key}
    EOT
  }
}
resource "yandex_vpc_security_group" "sg_vm" {
  name       = "dns-server-sg"
  network_id = yandex_vpc_network.network-vm.id
  ingress {
    protocol       = "TCP"
    description    = "SSH"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }
  ingress {
    protocol       = "TCP"
    description    = "Nginx"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 80
  }
  ingress {
    protocol       = "TCP"
    description    = "MinIO"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 9000
  }
  ingress {
    protocol       = "TCP"
    description    = "TCP NFS"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 2049
  }
  ingress {
    protocol       = "UDP"
    description    = "UDP NFS"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 2049
  }
  egress {
    protocol       = "ANY"
    description    = "outgoing"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}
