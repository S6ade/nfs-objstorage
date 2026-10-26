terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
	  version = "~> 0.100"
    }
  }
  required_version = ">= 1.0"
}

provider "yandex" {
  zone                     = var.zone
  cloud_id                 = var.cloud_id
  folder_id                = var.folder_id
  service_account_key_file = "key.json"
}