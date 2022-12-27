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
variable "serviceAccountID" {
  type = string
}
variable "ConnectionID" {
  type = string
}
variable "DBUser" {
  type = string
}
variable "DBHost" {
  type = string
}
variable "ServiceAccountAccessKey" {
  type = string
}
variable "ServiceAccountSecretKey" {
  type = string
}
provider "yandex" {
  cloud_id  = var.cloudID
  folder_id = var.folderID
  token     = var.token
}

resource "yandex_vpc_network" "vpcNetwork" {
  name        = "ya-vpc-network"
  description = "VPC Network created by Terraform"
}

resource "yandex_vpc_subnet" "vpcSubnet" {
  depends_on = [
    yandex_vpc_network.vpcNetwork
  ]
  v4_cidr_blocks = ["192.168.0.0/16"]
  zone           = var.zone
  network_id     = yandex_vpc_network.vpcNetwork.id
  description    = "VPC Subnet created by Terraform"
}

resource "yandex_mdb_postgresql_cluster" "postgresCluster" {
  name        = "my-pg-database"
  description = "PostgreSQL cluster created by Terraform"
  environment = "PRODUCTION"
  network_id  = yandex_vpc_network.vpcNetwork.id
  config {
    version = 13
    resources {
      resource_preset_id = "b2.nano"
      disk_type_id       = "network-hdd"
      disk_size          = 10
    }
    access {
      serverless = true
      web_sql    = true
    }
  }
  host {
    zone      = var.zone
    subnet_id = yandex_vpc_subnet.vpcSubnet.id
  }
}

resource "yandex_mdb_postgresql_user" "postgresUser" {
  cluster_id = yandex_mdb_postgresql_cluster.postgresCluster.id
  name       = "user1"
  password   = "user1user1"
}

resource "yandex_mdb_postgresql_database" "postgresDB" {
  name       = "db1"
  cluster_id = yandex_mdb_postgresql_cluster.postgresCluster.id
  owner      = yandex_mdb_postgresql_user.postgresUser.name
}


resource "yandex_function" "func" {
  name               = "function-for-postgres"
  memory             = "256"
  user_hash          = "v2"
  execution_timeout  = 5
  runtime            = "python37"
  entrypoint         = "function-for-postgresql.entry"
  service_account_id = var.serviceAccountID
  environment = {
    "VERBOSE_LOG"   = "True"
    "CONNECTION_ID" = var.ConnectionID
    "DB_USER"       = var.DBUser
    "DB_HOST"       = var.DBHost
  }
  content {
    zip_filename = "function-for-postgresql.zip"
  }
}

resource "yandex_function" "func2" {
  name               = "function-for-user-requests"
  memory             = "256"
  user_hash          = "v1"
  execution_timeout  = 5
  runtime            = "python37"
  entrypoint         = "function-for-user-requests.handler"
  service_account_id = var.serviceAccountID
  environment = {
    "VERBOSE_LOG"   = "True"
    "CONNECTION_ID" = var.ConnectionID
    "DB_USER"       = var.DBUser
    "DB_HOST"       = var.DBHost
  }
  content {
    zip_filename = "function-for-user-requests.zip"
  }
}

/*
resource "yandex_function_trigger" "triggerTimer" {
    name = "trigger-for-postgresql"
    description = "Trigger for PostgreSQL"
    timer {
      cron_expression = "* * * * ? *"
    }
    function {
      id = yandex_function.func.id
      service_account_id = var.serviceAccountID
    }
    
}
*/

resource "yandex_api_gateway" "apiGateway" {
  name        = "my-api-gateway"
  description = "My first API Gateway"
  spec        = <<-EOT
openapi: 3.0.0
info:
  title: Test API
  version: 1.0.0
paths:
  /hello:
    get:
      x-yc-apigateway-integration:
        type: dummy
        http_code: 200
        http_headers:
          Content-Type: text/plain
        content:
          'text/plain': "Hello, World!" 
  /byebye:
    get:
      x-yc-apigateway-integration:
        type: dummy
        http_code: 200
        http_headers:
          Content-type: text/plain
        content:
          'text/plain': "Bye-bye, cruel world!"
EOT

}


resource "yandex_api_gateway" "apiGatewayV2" {
  name        = "hello-world"
  description = "Hello World gateway"
  spec        = <<-EOT
openapi: "3.0.0"
info:
  version: 1.0.0
  title: Updated API
paths:
  /hello:
    get:
      summary: Say hello
      operationId: hello
      parameters:
        - name: user
          in: query
          description: User name to appear in greetings
          required: false
          schema:
            type: string
            default: 'world'
      responses:
        '200':
          description: Greeting
          content:
            'text/plain':
              schema:
                type: "string"
      x-yc-apigateway-integration:
        type: dummy
        http_code: 200
        http_headers:
          'Content-Type': "text/plain"
        content:
          'text/plain': "Hello, {user}!\n"
  /results:
    get:
      operationId: function-for-user-requests
      x-yc-apigateway-integration:
        type: cloud-functions
        function_id: ${yandex_function.func2.id}
        service_account_id: ${var.serviceAccountID}
  /check:
      get:
          x-yc-apigateway-integration:
            type: cloud-functions
            function_id: ${yandex_function.queue-function.id}
            service_account_id: ${var.serviceAccountID}
          operationId: add-url
EOT
}

resource "yandex_message_queue" "queue" {
  name       = "my-first-queue"
  access_key = var.ServiceAccountAccessKey
  secret_key = var.ServiceAccountSecretKey
}

resource "yandex_function" "queue-function" {
  name               = "my-url-receiver-function"
  description        = "function for URL"
  user_hash          = "v2"
  memory             = "256"
  execution_timeout  = 5
  runtime            = "python37"
  entrypoint         = "my-url-receiver-function.handler"
  service_account_id = var.serviceAccountID
  environment = {
    "VERBOSE_LOG"           = "True"
    "AWS_ACCESS_KEY_ID"     = var.ServiceAccountAccessKey
    "AWS_SECRET_ACCESS_KEY" = var.ServiceAccountSecretKey
    "QUEUE_URL"             = yandex_message_queue.queue.id
  }
  content {
    zip_filename = "my-url-receiver-function.zip"
  }
}

resource "yandex_function" "url-from-mq" {
  name               = "function-for-url-from-mq"
  description        = "function for URL from Message Queue"
  user_hash          = "v1"
  memory             = "256"
  execution_timeout  = 5
  runtime            = "python37"
  entrypoint         = "function-for-url-from-mq.handler"
  service_account_id = var.serviceAccountID
  environment = {
    "VERBOSE_LOG"           = "True"
    "AWS_ACCESS_KEY_ID"     = var.ServiceAccountAccessKey
    "AWS_SECRET_ACCESS_KEY" = var.ServiceAccountSecretKey
    "QUEUE_URL"             = yandex_message_queue.queue.id
    "CONNECTION_ID"         = var.ConnectionID
    "DB_USER"               = var.DBUser
    "DB_HOST"               = var.DBHost

  }
  content {
    zip_filename = "function-for-url-from-mq.zip"
  }

}

resource "yandex_function_trigger" "triggerTimerMQ" {
    name = "trigger-for-mq"
    description = "Trigger for Message Queue"
    timer {
      cron_expression = "* * * * ? *"
    }
    function {
      id = yandex_function.url-from-mq.id
      service_account_id = var.serviceAccountID
    }
    
}