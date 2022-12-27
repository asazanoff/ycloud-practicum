terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}
variable "cloudID" {
  type = string
}
variable "folderID" {
  type = string
}
variable "token" {
  type = string
}
variable "zone" {
  type = string
}

provider "yandex" {
  cloud_id  = var.cloudID
  folder_id = var.folderID
  token     = var.token
  zone      = var.zone
}

resource "yandex_compute_instance" "vm-private" { #no ip address
  name = "security-training-vm1"
  boot_disk {
    initialize_params {
      image_id = "fd8j8o5bguvqglmqls7q"
    }
  }
  platform_id = "standard-v1"
  resources {
    cores  = 2
    memory = 4
  }
  network_interface {
    subnet_id = "e9bf7cfgsfcka2ae88lp"
  }
  service_account_id = "###SERVICEACCOUNT###"
  metadata = {
    user-data = file("metadata.txt")
  }
}

resource "yandex_vpc_network" "network" {
  name = "security-training-network"
}

resource "yandex_vpc_subnet" "subnet" {
  name           = "security-training-subnet"
  network_id     = yandex_vpc_network.network.id
  v4_cidr_blocks = ["10.128.0.0/24"]
}

resource "yandex_compute_instance" "vm-sec-first" { #reserved ip address
  name = "ipsec-training-gateway"
  boot_disk {
    initialize_params {
      image_id = "fd8sr6lojbg41a5a64qg"
    }
  }
  platform_id = "standard-v1"
  resources {
    cores  = 2
    memory = 4
  }
  network_interface {
    subnet_id      = "e9bf7cfgsfcka2ae88lp"
    nat            = true
    ipv4           = true
    nat_ip_address = "51.250.88.138"
  }
  metadata = {
    user-data = file("metadata.txt")
  }
  service_account_id = "###SERVICEACCOUNT###"
}

resource "yandex_compute_instance" "vm-sec-second" { #random ip
  name = "ipsec-training-remote"
  boot_disk {
    initialize_params {
      image_id = "fd8sr6lojbg41a5a64qg"
    }
  }
  platform_id = "standard-v1"
  resources {
    cores  = 2
    memory = 4
  }
  network_interface {
    subnet_id      = yandex_vpc_subnet.subnet.id
    nat            = true
    ipv4           = true
  }
  metadata = {
    user-data = file("metadata.txt")
  }
  service_account_id = "###SERVICEACCOUNT###"
}

output "REMOTE_IPV4" {
  value = yandex_compute_instance.vm-sec-second.network_interface.0.nat_ip_address
}
