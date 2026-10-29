"""Nightly encrypted-in-transit database dump, gzip, S3 upload and SNS notification."""
import datetime as dt
import gzip
import json
import logging
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import boto3

logging.basicConfig(filename='/var/log/db-backup.log', level=logging.INFO,
                    format='%(asctime)s %(levelname)s %(message)s')
region = os.environ['AWS_DEFAULT_REGION']
sm = boto3.client('secretsmanager', region_name=region)
s3 = boto3.client('s3', region_name=region)
sns = boto3.client('sns', region_name=region)
folder = Path('/var/backups/bluefin')

def notify(message):
    sns.publish(TopicArn=os.environ['SNS_TOPIC_ARN'], Subject='Bluefin database backup', Message=message)

def main():
    folder.mkdir(parents=True, exist_ok=True, mode=0o700)
    destination = None
    try:
        secret = json.loads(sm.get_secret_value(SecretId=os.environ['DB_SECRET_ARN'])['SecretString'])
        filename = dt.datetime.now(dt.timezone.utc).strftime('%Y-%m-%d.sql.gz')
        destination = folder / filename
        # Password is in a temporary mode-0600 client configuration, never command arguments.
        with tempfile.TemporaryDirectory(prefix='bluefin-dump-') as temp:
            options = Path(temp) / 'client.cnf'
            options.write_text('[client]\nhost=' + secret['host'] + '\nuser=' + secret['username'] +
                               '\npassword=' + secret['password'] + '\nport=3306\n')
            options.chmod(0o600)
            dump = shutil.which('mariadb-dump') or shutil.which('mysqldump')
            if not dump:
                raise RuntimeError('Database dump client unavailable')
            # Hostname is the private CNAME, so verify the RDS CA chain without hostname matching.
            command = [dump, '--defaults-extra-file=' + str(options), '--single-transaction',
                       '--skip-lock-tables', '--skip-triggers', '--no-tablespaces',
                       '--ssl', '--ssl-ca=/opt/bluefin/global-bundle.pem',
                       secret['database']]
            # Write raw output to a private temporary file; do not log SQL/data or credentials.
            sql = Path(temp) / 'dump.sql'
            with sql.open('wb') as stream:
                sql.chmod(0o600)
                result = subprocess.run(command, stdout=stream, stderr=subprocess.PIPE, timeout=900)
            if result.returncode:
                raise RuntimeError('Dump client failed; inspect database privileges/TLS/connectivity')
            with sql.open('rb') as stream, gzip.open(destination, 'wb') as output:
                shutil.copyfileobj(stream, output)
            destination.chmod(0o600)
        key = 'db/' + filename
        s3.upload_file(str(destination), os.environ['BACKUP_BUCKET'], key,
                       ExtraArgs={'ServerSideEncryption': 'AES256'})
        # At most seven dated local copies; S3 lifecycle retains uploaded dumps for 30 days.
        for old in sorted(folder.glob('*.sql.gz'))[:-7]:
            old.unlink()
        # Also clean files older than seven days using find, as required by the assignment.
        subprocess.run(['find', str(folder), '-type', 'f', '-name', '*.sql.gz', '-mtime', '+6', '-delete'], check=True)
        logging.info('SUCCESS s3://%s/%s', os.environ['BACKUP_BUCKET'], key)
        notify('SUCCESS: database dump uploaded to s3://' + os.environ['BACKUP_BUCKET'] + '/' + key)
    except Exception as exc:
        logging.error('FAILURE %s', type(exc).__name__)
        if destination is not None and destination.exists():
            destination.unlink()
        try:
            notify('FAILURE: nightly database backup failed. Review /var/log/db-backup.log on the backup host.')
        except Exception:
            logging.error('SNS failure notification could not be sent')
        raise SystemExit(1)

if __name__ == '__main__':
    main()
