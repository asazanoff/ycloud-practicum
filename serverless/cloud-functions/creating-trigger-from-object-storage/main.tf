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
variable "access_key" {
  type = string
}
variable "secret_key" {
  type = string
}

provider "yandex" {
  cloud_id  = var.cloudID
  folder_id = var.folderID
  token     = var.token
}

resource "yandex_storage_bucket" "bucket" {
  access_key            = var.access_key
  secret_key            = var.secret_key
  bucket                = "bucket-for-trigger-ivane"
  acl                   = "public-read-write"
  max_size              = 1073741824
  default_storage_class = "STANDARD"
  folder_id             = var.folderID
}
