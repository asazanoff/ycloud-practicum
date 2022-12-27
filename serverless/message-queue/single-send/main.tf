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
}

// Adding service account and binding multiple roles
resource "yandex_iam_service_account" "serviceAccount" {
  name        = "ffmpeg-account-for-cf"
  description = "service account for serverless"
}
resource "yandex_resourcemanager_folder_iam_binding" "serviceAccountBinding" {
  folder_id = var.folderID
  depends_on = [
    yandex_iam_service_account.serviceAccount
  ]
  for_each = {
    "storage.viewer"               = "storage.viewer"
    "storage.uploader"             = "storage.uploader"
    "storage.editor"               = "storage.editor"
    "ymq.reader"                   = "ymq.reader"
    "ymq.writer"                   = "ymq.writer"
    "ymq.admin"                    = "ymq.admin"
    "ydb.admin"                    = "ydb.admin"
    "serverless.functions.invoker" = "serverless.functions.invoker"
    "lockbox.payloadViewer"        = "lockbox.payloadViewer"
  }
  role    = each.value
  members = ["serviceAccount:${yandex_iam_service_account.serviceAccount.id}"]
}
resource "yandex_iam_service_account_static_access_key" "serviceAccountAccessKey" {
  depends_on = [
    yandex_resourcemanager_folder_iam_binding.serviceAccountBinding
  ]
  service_account_id = yandex_iam_service_account.serviceAccount.id
  description        = "Static key for Service Account"
}

//Adding secrets in lockbox
resource "yandex_lockbox_secret" "lockboxSecret" {
  folder_id   = var.folderID
  description = "Keys for serverless"
  name        = "ffmpeg-sa-key"
  depends_on = [
    yandex_iam_service_account_static_access_key.serviceAccountAccessKey
  ]
}
resource "yandex_lockbox_secret_version" "lockboxSecret" {
  secret_id = yandex_lockbox_secret.lockboxSecret.id
  entries {
    key        = "ACCESS_KEY_ID"
    text_value = yandex_iam_service_account_static_access_key.serviceAccountAccessKey.access_key
  }
  entries {
    key        = "SECRET_ACCESS_KEY"
    text_value = yandex_iam_service_account_static_access_key.serviceAccountAccessKey.secret_key
  }
  depends_on = [
    yandex_lockbox_secret.lockboxSecret
  ]
}

//Create message queue
resource "yandex_message_queue" "messageQueue" {
  name       = "ffmpeg"
  access_key = yandex_iam_service_account_static_access_key.serviceAccountAccessKey.access_key
  secret_key = yandex_iam_service_account_static_access_key.serviceAccountAccessKey.secret_key
  depends_on = [
    yandex_lockbox_secret_version.lockboxSecret
  ]
}

// Create simple serverless YDB
resource "yandex_ydb_database_serverless" "ydbServerless" {
  name      = "ffmpeg"
  folder_id = var.folderID
}

//Configure AWS CLI to upload database template
//Also uploading python file and ffmpeg util
resource "null_resource" "createTable" {
  provisioner "local-exec" {
    command = "aws configure set aws_access_key_id ${yandex_iam_service_account_static_access_key.serviceAccountAccessKey.access_key}"
  }
  provisioner "local-exec" {
    command = "aws configure set aws_secret_access_key ${yandex_iam_service_account_static_access_key.serviceAccountAccessKey.secret_key}"
  }
  provisioner "local-exec" {
    command = "aws configure set default.region ${yandex_ydb_database_serverless.ydbServerless.location_id}"
  }
  provisioner "local-exec" {
    command = "aws dynamodb create-table --cli-input-json file://tasks.json --endpoint-url ${yandex_ydb_database_serverless.ydbServerless.document_api_endpoint} --region ${yandex_ydb_database_serverless.ydbServerless.location_id}"
  }
  depends_on = [
    yandex_ydb_database_serverless.ydbServerless
  ]
}
resource "null_resource" "createZIP" {
  provisioner "local-exec" {
    command = "zip src.zip index.py requirements.txt ffmpeg"
  }
  depends_on = [
    null_resource.createTable
  ]
}

//Creating bucket and uploading ZIP file
resource "yandex_storage_bucket" "createObjectStorage" {
  bucket     = "storage-for-ffmpeg-ie"
  access_key = yandex_iam_service_account_static_access_key.serviceAccountAccessKey.access_key
  secret_key = yandex_iam_service_account_static_access_key.serviceAccountAccessKey.secret_key
  depends_on = [
    null_resource.createZIP
  ]
}
resource "yandex_storage_object" "uploadToBucket" {
  bucket     = yandex_storage_bucket.createObjectStorage.bucket
  access_key = yandex_iam_service_account_static_access_key.serviceAccountAccessKey.access_key
  secret_key = yandex_iam_service_account_static_access_key.serviceAccountAccessKey.secret_key

  key    = "src.zip"
  source = "src.zip"
  depends_on = [
    yandex_storage_bucket.createObjectStorage
  ]
}

//Creating cloud functions and trigger
//Maybe it could be shorten
resource "yandex_function" "ffmpeg-api" {
  user_hash          = "v2"
  name               = "ffmpeg-api"
  description        = "Function for FFMPEG API"
  memory             = 256
  execution_timeout  = 5
  runtime            = "python37"
  entrypoint         = "index.handle_api"
  service_account_id = yandex_iam_service_account.serviceAccount.id
  environment = {
    "SECRET_ID"       = yandex_lockbox_secret.lockboxSecret.id
    "YMQ_QUEUE_URL"   = yandex_message_queue.messageQueue.id
    "DOCAPI_ENDPOINT" = yandex_ydb_database_serverless.ydbServerless.document_api_endpoint
  }
  package {
    bucket_name = yandex_storage_object.uploadToBucket.bucket
    object_name = yandex_storage_object.uploadToBucket.key
  }
  depends_on = [
    yandex_storage_object.uploadToBucket
  ]
}
resource "yandex_function" "ffmpeg-converter" {
  user_hash          = "v2"
  name               = "ffmpeg-converter"
  description        = "Function for FFMPEG Converter"
  memory             = 2048
  execution_timeout  = 600
  runtime            = "python37"
  entrypoint         = "index.handle_process_event"
  service_account_id = yandex_iam_service_account.serviceAccount.id
  environment = {
    "SECRET_ID"       = yandex_lockbox_secret.lockboxSecret.id
    "YMQ_QUEUE_URL"   = yandex_message_queue.messageQueue.id
    "DOCAPI_ENDPOINT" = yandex_ydb_database_serverless.ydbServerless.document_api_endpoint
    "S3_BUCKET"       = yandex_storage_object.uploadToBucket.bucket
  }
  package {
    bucket_name = yandex_storage_object.uploadToBucket.bucket
    object_name = yandex_storage_object.uploadToBucket.key
  }
  depends_on = [
    yandex_storage_object.uploadToBucket
  ]
}
resource "yandex_function_trigger" "trigger" {
  name        = "ffmpeg"
  description = "Trigger for FFMPEG"
  function {
    id                 = yandex_function.ffmpeg-converter.id
    service_account_id = yandex_iam_service_account.serviceAccount.id
  }
  message_queue {
    queue_id           = yandex_message_queue.messageQueue.arn
    service_account_id = yandex_iam_service_account.serviceAccount.id
    batch_size         = 1
    batch_cutoff       = 10
  }
  depends_on = [
    yandex_function.ffmpeg-converter
  ]
}


