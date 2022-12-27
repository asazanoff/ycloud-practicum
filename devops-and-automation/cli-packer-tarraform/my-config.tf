/*
Terraform file for lesson in Yandex Practicum (ycloud)
Provider version 0.84.0
Uses variables from terraform.tfvars file
Creates Compute Instance with image (created with Packer)
Creates network and subnet
Creates Postgres cluster with one user and one database
Prints VM's internal and external IP addresses
*/
terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

variable "defaultZone" {
  type = string
}
variable "cloudID" {
  type = string
}
variable "folderID" {
  type = string
}
variable "imageID" {
  type = string
}
variable "postgresPass" {
  type = string
}

provider "yandex" {
  //service_account_key_file = "~/yandex-cloud/serviceacckey.json"
  zone      = var.defaultZone
  cloud_id  = var.cloudID
  folder_id = var.folderID
}

resource "yandex_compute_instance" "vm-1" {
  name        = "from-terraform-vm"
  platform_id = "standard-v1"
  zone        = var.defaultZone
  resources {
    cores  = 2
    memory = 4
  }
  boot_disk {
    initialize_params {
      image_id = var.imageID
    }
  }
  network_interface {
    subnet_id = yandex_vpc_subnet.subnet-1.id
    nat       = true
  }
  metadata = {
    "ssh-keys" = "${file("~/.ssh/id_rsa.pub")}"
  }

}

resource "yandex_vpc_network" "network-1" {
  name = "from-terraform-network"
}

resource "yandex_vpc_subnet" "subnet-1" {
  name       = "from-terraform-subnet"
  network_id = yandex_vpc_network.network-1.id
  depends_on = [
    yandex_vpc_network.network-1
  ]
  v4_cidr_blocks = ["10.0.0.0/16"]
  zone           = var.defaultZone
}

resource "yandex_mdb_postgresql_cluster" "postgres-cluster" {
  name        = "from-terraform-postgres-cluster"
  environment = "PRESTABLE"
  network_id  = yandex_vpc_network.network-1.id
  config {
    version = 15
    resources {
      resource_preset_id = "s2.micro"
      disk_type_id       = "network-ssd"
      disk_size          = 16
    }
  }
  host {
    zone      = var.defaultZone
    subnet_id = yandex_vpc_subnet.subnet-1.id
  }
}

resource "yandex_mdb_postgresql_user" "postgres-user" {
  cluster_id = yandex_mdb_postgresql_cluster.postgres-cluster.id
  name       = "alice"
  password   = var.postgresPass
  depends_on = [
    yandex_mdb_postgresql_cluster.postgres-cluster
  ]
}

resource "yandex_mdb_postgresql_database" "postgres-db" {
  cluster_id = yandex_mdb_postgresql_cluster.postgres-cluster.id
  name       = "testdb"
  owner      = yandex_mdb_postgresql_user.postgres-user.name
  depends_on = [
    yandex_mdb_postgresql_user.postgres-user
  ]
}

output "internal_ip_address_vm-1" {
  value = yandex_compute_instance.vm-1.network_interface.0.ip_address
}
output "external_ip_address_vm-1" {
  value = yandex_compute_instance.vm-1.network_interface.0.nat_ip_address

}
