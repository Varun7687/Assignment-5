"""Initialize the lab schema and restricted app user. Runs only on the backup host."""
import json
import os
import time
import boto3
import pymysql

region = os.environ['AWS_DEFAULT_REGION']
sm = boto3.client('secretsmanager', region_name=region)

def secret(arn):
    return json.loads(sm.get_secret_value(SecretId=arn)['SecretString'])

def initialize():
    master = secret(os.environ['MASTER_SECRET_ARN'])
    app = secret(os.environ['DB_SECRET_ARN'])
    with pymysql.connect(
        host=master['host'], port=3306, user=master['username'], password=master['password'],
        database='inventory', connect_timeout=10,
        ssl_ca='/opt/bluefin/global-bundle.pem', ssl_verify_cert=True, ssl_verify_identity=False
    ) as conn, conn.cursor() as cursor:
        cursor.execute('''CREATE TABLE IF NOT EXISTS items (
          id INT PRIMARY KEY AUTO_INCREMENT,
          item_name VARCHAR(160) NOT NULL,
          sku VARCHAR(64) NOT NULL UNIQUE,
          quantity INT NOT NULL,
          warehouse_location VARCHAR(120) NOT NULL,
          last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        )''')
        cursor.execute("CREATE USER IF NOT EXISTS %s@'%%' IDENTIFIED BY %s", (app['username'], app['password']))
        cursor.execute("ALTER USER %s@'%%' IDENTIFIED BY %s REQUIRE SSL", (app['username'], app['password']))
        cursor.execute("GRANT SELECT, INSERT, UPDATE, DELETE ON inventory.* TO %s@'%%'", (app['username'],))
        for i in range(1, 11):
            cursor.execute('INSERT IGNORE INTO items (id,item_name,sku,quantity,warehouse_location) VALUES (%s,%s,%s,%s,%s)',
                           (i, f'Demo item {i}', f'BLUEFIN-{i:03d}', i * 5, f'Rack {i}'))
        conn.commit()

if __name__ == '__main__':
    for attempt in range(120):
        try:
            initialize()
            print('Schema, ten seed rows and restricted application user are ready.')
            break
        except Exception as exc:
            # Avoid printing credentials/SQL exception details into user-data logs.
            print(f'Bootstrap attempt {attempt + 1} not ready: {type(exc).__name__}', flush=True)
            time.sleep(10)
    else:
        raise SystemExit('Database bootstrap failed. Review DNS, IAM, routes and security groups.')
