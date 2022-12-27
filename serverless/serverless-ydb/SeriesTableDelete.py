import boto3
from endpoint import endpointURL

def delete_serie_table():
    ydb_docapi_client = boto3.resource('dynamodb', endpoint_url = endpointURL)

    table = ydb_docapi_client.Table('docapitest/series')
    table.delete()

if __name__ == '__main__':
    delete_serie_table()
    print("Table Series deleted")