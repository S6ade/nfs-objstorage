variable "serv_configs" {
  description = "setting serv & client VM"
  type = map(any)
}
variable "cloud_id" { type = string }
variable "folder_id" { type = string }
variable "ssh_public_key" { type = string }
variable "zone" {
   type = string
   default = "ru-central1-d"
}