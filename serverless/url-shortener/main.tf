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
variable "sa-key" {
  default = "serverless-shortener.sa"
}

locals {
  ydb-common-command = "ydb --endpoint ${yandex_ydb_database_serverless.ydbServerless.ydb_api_endpoint} --database ${yandex_ydb_database_serverless.ydbServerless.database_path} --sa-key-file ${var.sa-key} "
}
provider "yandex" {
  cloud_id  = var.cloudID
  folder_id = var.folderID
  token     = var.token
}
resource "yandex_iam_service_account" "serviceAccount" {
  name        = "serverless-shortener"
  description = "service account for serverless practice 2"
}

output "SERVICE_ACCOUNT_SHORTENER_ID" {
  value = yandex_iam_service_account.serviceAccount.id
}

resource "yandex_resourcemanager_folder_iam_binding" "serviceAccountBinding" {
  folder_id = var.folderID
  for_each = {
    "editor"         = "editor"
    "storage.viewer" = "storage.viewer"
    "ydb.admin"      = "ydb.admin"
  }
  role    = each.value
  members = ["serviceAccount:${yandex_iam_service_account.serviceAccount.id}"]
  depends_on = [
    yandex_iam_service_account.serviceAccount
  ]
}
resource "yandex_iam_service_account_static_access_key" "serviceAccountAccessKey" {
  service_account_id = yandex_iam_service_account.serviceAccount.id
  description        = "Static key for Service Account"
  depends_on = [
    yandex_resourcemanager_folder_iam_binding.serviceAccountBinding
  ]

}

resource "yandex_storage_bucket" "createObjectStorage" {
  bucket     = "storage-for-serverless-shortener-ie"
  acl        = "public-read-write"
  max_size   = 1073741824
  anonymous_access_flags {
    list = true
    read = true
  }
  access_key = yandex_iam_service_account_static_access_key.serviceAccountAccessKey.access_key
  secret_key = yandex_iam_service_account_static_access_key.serviceAccountAccessKey.secret_key
  depends_on = [
    yandex_iam_service_account_static_access_key.serviceAccountAccessKey
  ]
}

resource "yandex_storage_object" "uploadToBucket" {
  bucket     = yandex_storage_bucket.createObjectStorage.bucket
  access_key = yandex_iam_service_account_static_access_key.serviceAccountAccessKey.access_key
  secret_key = yandex_iam_service_account_static_access_key.serviceAccountAccessKey.secret_key
  key        = "index.html"
  source     = "index.html"
  //acl = "public-read"
  content_type = "text/html; charset=utf-8"
  depends_on = [
    yandex_storage_bucket.createObjectStorage
  ]
}

// Create simple serverless YDB
resource "yandex_ydb_database_serverless" "ydbServerless" {
  name      = "for-serverless-shortener"
  folder_id = var.folderID
}

resource "null_resource" "ydbActions" {
  provisioner "local-exec" {
    command = "yc iam key create --service-account-name ${yandex_iam_service_account.serviceAccount.name} --output ${var.sa-key}"
  }
  provisioner "local-exec" {
    command = "${local.ydb-common-command} discovery whoami --groups"
  }
  provisioner "local-exec" {
    command = "${local.ydb-common-command} scripting yql --file links.yql"
  }
  provisioner "local-exec" {
    command = "${local.ydb-common-command} scheme describe links"
  }
  depends_on = [
    yandex_storage_bucket.createObjectStorage
  ]
}

resource "null_resource" "py-requirements" {
  provisioner "local-exec" {
    command = "pipreqs $PWD --force"
  }
}

resource "null_resource" "zip" {
  provisioner "local-exec" {
    command = "zip src.zip index.py requirements.txt "
  }
  depends_on = [
    null_resource.py-requirements
  ]
}


resource "yandex_function" "func" {
  user_hash          = "v4"
  name               = "for-serverless-shortener"
  description        = "Function for serverless shortener"
  memory             = 256
  execution_timeout  = 5
  runtime            = "python37"
  entrypoint         = "index.handler"
  service_account_id = yandex_iam_service_account.serviceAccount.id
  environment = {
    "USE_METADATA_CREDENTIALS" = "1"
    "endpoint"                 = "grpcs://${yandex_ydb_database_serverless.ydbServerless.ydb_api_endpoint}"
    "database"                 = yandex_ydb_database_serverless.ydbServerless.database_path
  }
  content {
    zip_filename = "src.zip"
  }
  depends_on = [
    null_resource.zip
  ]
}

resource "yandex_function_iam_binding" "makeFunctionPublic" {
  function_id = yandex_function.func.id
  role        = "serverless.functions.invoker"
  members     = ["system:allUsers"]
  depends_on = [
    yandex_function.func
  ]
}

resource "yandex_api_gateway" "apiGateway" {
  name        = "for-serverless-shortener"
  description = "For serverless shortener"
  spec = templatefile("for-serverless-shortener.yml.tpl", {
    bucket          = yandex_storage_bucket.createObjectStorage.bucket
    object          = yandex_storage_object.uploadToBucket.key
    service_account = yandex_iam_service_account.serviceAccount.id
    function_id     = yandex_function.func.id
  })
  depends_on = [
    yandex_storage_object.uploadToBucket
  ]

}
