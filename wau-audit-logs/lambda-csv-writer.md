```python
import os
import time
import datetime
import csv
import json
from io import StringIO
import logging
import boto3
from botocore.config import Config
import uuid

SECOND_PER_MIN = 60
MS_PER_SEC = 1000

# Setup logging. Beware that enabling DEBUG level logs produces a lot of output
# from the boto3 and botocore libraries.
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger('audit-log-lambda')
logger.setLevel(logging.INFO)

boto_clients = {}


def get_client(name):
    """
    Helper function to get the desired boto client.

    :param name: Name of the client to return, e.g. "ecs", "codedeploy"
    """
    client = boto_clients.get(name)

    # As per https://boto3.amazonaws.com/v1/documentation/api/latest/guide/retries.html
    # we increase the number attempts to deal with ThrottlingException seen during
    # multiple calls to get_log_events().  This does exponential backoff.
    config = Config(
        retries={
            'max_attempts': 25,
            'mode': 'adaptive'
        }
    )

    if client is None:
        client = boto3.client(name, config=config)
        boto_clients[name] = client
    return client


def get_active_streams(group, mins, padding_mins=90, prefix=""):
    """Return all streams in the supplied Cloudwatch group where the stream has
    events newer than the supplied number of minutes before now, with padding"""

    client = get_client('logs')
    mins_prior = mins + padding_mins
    start_time_ms = (int(time.time()) - SECOND_PER_MIN * mins_prior) * MS_PER_SEC
    streams = []

    paginator = client.get_paginator('describe_log_streams')
    log_stream_args = dict(logGroupName=group,
                           orderBy='LastEventTime',
                           descending=True)
    for response in paginator.paginate(**log_stream_args):
        for stream in response['logStreams']:
            if stream['lastIngestionTime'] >= start_time_ms or \
                    stream['lastEventTimestamp'] >= start_time_ms:
                streams.append(stream['logStreamName'])

    filtered = [x for x in streams if x.startswith(prefix)] if prefix else streams

    logger.info(f'found a total of {len(filtered)} matching streams')
    return filtered


def get_events(group, streams, mins, padding_mins=60):
    """Get Cloudwatch logs from all streams in the supplied group that are newer than
    the number of minutes in the past"""
    client = get_client('logs')

    end_time_ms = int(time.time()) * MS_PER_SEC
    start_time_ms = end_time_ms - mins * SECOND_PER_MIN * MS_PER_SEC
    # Padding to include messages with old timestamps that haven't been ingested yet
    padded_ms = padding_mins * SECOND_PER_MIN * MS_PER_SEC

    all_events = []
    paginator = client.get_paginator('filter_log_events')

    # filter_log_events can handle a max of 100 streams per call
    streams_per_call = 100
    for idx in range(0, len(streams), streams_per_call):
        streams_subset = streams[idx:idx + streams_per_call]
        filter_args = dict(logGroupName=group,
                           logStreamNames=streams_subset,
                           startTime=start_time_ms - padded_ms,
                           endTime=end_time_ms)
        logger.info(f'fetching events from streams: [{idx}:{idx + streams_per_call}]')
        for response in paginator.paginate(**filter_args):
            all_events.extend(response['events'])

    logger.info('sorting events by timestamp')
    sorted_events = sorted(all_events, key=lambda event: event['timestamp'])

    filtered_events = [x for x in sorted_events if x['timestamp'] >= start_time_ms
                       or x['ingestionTime'] >= start_time_ms]

    # convert the 'message' from a JSON string to a native Python object
    logger.info('converting events from JSON string to native objects')
    for event in filtered_events:
        event['message'] = json.loads(event['message'])

    logger.info(f'found a total of {len(filtered_events)} events')
    return filtered_events


def object_key(mins, env_name, extension):
    date_format = '%b-%d-%Y-%H:%M:%S'
    end = datetime.datetime.now()
    start = end - datetime.timedelta(minutes=mins)
    start_str = start.strftime(date_format)
    end_str = end.strftime(date_format)
    return f'{extension}/{env_name}-{start_str}--{end_str}.{extension}'


def write_json(s3_client, env_name, mins, events, bucket):
    """Write the events object as a JSON file to S3"""
    key = object_key(mins, env_name, 'json')
    body = json.dumps(events, indent=2)
    logger.info(f'writing audit log JSON object to S3 bucket: {bucket}, key: {key}')
    s3_client.put_object(Body=body, Bucket=bucket, Key=key)


def csv_data(events, env_name):
    """Write events to an in-memory CSV file and return it's file object, so we can handle
    large files in RAM"""

    # Using a StringIO object instead of writing to disk.  Lambda has a max tmp space of 512 MB
    # but we can get a large amount of RAM if required, so use an in-memory file.  BytesIO would
    # be ideal but the csv module writes strings.
    tmp = StringIO()

    # Using a dict to keep track of the ordered and unique keys present in all events.  Python dict
    # keys are guaranteed to be ordered as of Python 3.7.
    header_names = {'id': None, 'timestamp': None, 'customer': None}
    for event in events:
        message = event['message']['message'].copy()
        details = message['details']
        del message['details']
        for key in {**message, **details}:
            header_names[key] = None

    # Ensure that ipAddress (PII) is not included as a field name
    if 'ipAddress' in header_names:
        del header_names['ipAddress']

    writer = csv.DictWriter(tmp, fieldnames=list(header_names.keys()))
    writer.writeheader()

    for event in events:
        message = event['message']['message']
        timestamp = time.gmtime(event['timestamp'] / MS_PER_SEC)
        
        writer.writerow({
            'id': uuid4(),
            'timestamp': time.strftime("%Y-%m-%d %H:%M:%S", timestamp),
            'customer': env_name,
            'event': message['event'],
            # IP addresses are PII so stripping from the CSV output
            # 'ipAddress': message['ipAddress'],
            'userAgent': message.get('userAgent'),
            **message['details'],
        })

    # S3 wants bytes so convert from string:
    tmp.seek(0)
    return bytes(tmp.getvalue(), encoding='utf-8')


def write_csv(s3_client, env_name, mins, audit_events, bucket):
    key = object_key(mins, env_name, 'csv')
    body = csv_data(audit_events, env_name)
    logger.info(f'writing audit log CSV object to S3 bucket: {bucket}, key: {key}')
    s3_client.put_object(Body=body, Bucket=bucket, Key=key)


def main():
    group = os.environ['AUDIT_LOGS_LOG_GROUP_NAME']
    stream_prefix = os.environ.get('AUDIT_LOGS_STREAM_PREFIX', "")
    mins = int(os.environ['AUDIT_LOGS_DURATION_MINS'])
    bucket = os.environ['AUDIT_LOGS_ARTIFACT_ACCESS_POINT']
    env_name = os.environ['ENV_NAME']
    log_format = os.environ['LOG_FORMAT']

    active_streams = get_active_streams(group, mins, prefix=stream_prefix)
    if len(active_streams) == 0:
        logger.info(f'No streams found with messages newer than {mins} mins old, exiting')
        return

    audit_events = get_events(group, active_streams, mins)
    s3_client = get_client('s3')

    if log_format == 'json':
        write_json(s3_client, env_name, mins, audit_events, bucket)
    elif log_format == 'csv':
        write_csv(s3_client, env_name, mins, audit_events, bucket)
    else:
        raise EnvironmentError('log_format must be either json or csv')


def handler(event, context):
    """
    Entrypoint function for Lambda. Gets the Cloudwatch logs for the audit logs
    from the past N minutes and writes an artifact to an S3 bucket.

    :param event: The custom resource event. (unused)
    :param context: Lambda context object passed in by AWS. (unused)
    :return: None
    """
    try:
        main()
    except Exception as e:
        logger.error(f'Caught unexpected error: {str(e)}')
        raise


# Test manually:
if __name__ == '__main__':
    main()
```
