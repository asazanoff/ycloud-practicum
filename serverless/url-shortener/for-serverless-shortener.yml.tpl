openapi: 3.0.0
info:
  title: for-serverless-shortener
  version: 1.0.0
paths:
  /:
    get:
      x-yc-apigateway-integration:
        type: object_storage
        bucket: ${bucket}        # <-- имя бакета
        object: ${object}          # <-- имя html-файла
        presigned_redirect: false
        service_account: ${service_account} # <-- идентификатор сервисного аккаунта
      operationId: static
  /shorten:
    post:
      x-yc-apigateway-integration:
        type: cloud_functions
        function_id: ${function_id}               # <-- идентификатор функции
      operationId: shorten
  /r/{id}:
    get:
      x-yc-apigateway-integration:
        type: cloud_functions
        function_id: ${function_id}               # <-- идентификатор функции
      operationId: redirect
      parameters:
        - description: id of the url
          explode: false
          in: path
          name: id
          required: true
          schema:
            type: string
          style: simple