import boto3
from endpoint import endpointURL


def create_series_table():
    ydb_docapi_client = boto3.resource('dynamodb', endpoint_url = endpointURL)

    table = ydb_docapi_client.create_table(
        TableName = 'docapitest/series', # Series — имя таблицы 
        KeySchema = [
            {
                'AttributeName': 'series_id',
                'KeyType': 'HASH'  # Ключ партицирования
            },
            {
                'AttributeName': 'title',
                'KeyType': 'RANGE'  # Ключ сортировки
            }
        ],
        AttributeDefinitions = [
            {
                'AttributeName': 'series_id',
                'AttributeType': 'N'  # Целое число
            },
            {
                'AttributeName': 'title',
                'AttributeType': 'S'  # Строка
            },

        ]
    )
    return table

if __name__ == '__main__':
    series_table = create_series_table()
    print("Table status:", series_table.table_status)