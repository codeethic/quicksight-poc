# Citrine - WAU Audit Log Analytics

## Objective

- Aggregate all wau audit log files into a centralized S3 bucket in the same region/account as Glue/Redshift.
- Invoke a Glue job to process each of the audit log files and load the data into Redshift for analytics.

## Required Changes to the Existing Process

- Add the customer field to the csv.
- Write the WAU audit log files, generated for each customer, to a new centralized S3 bucket in the same region/account as Glue and Redshift.
- Create a Lambda to invoke the Glue job based on EventBridge (CloudWatch Events) trigger with a cron expression.

## Configuration

### IAM Role

- Creation of the Lambda will create an IAM role automatically with the AWSLambdaBasicExecutionRole policy that will limit permissions per the JSON below. The downside is that it auto-generates a role name with a GUID appended which may not be desirable.
- If you choose to explicitly create a new IAM role that the lambda function can assume, ensure you assign the required policies and permissions accordingly.
- Required policies: AWSLambdaBasicExecutionRole, AWSGlueServiceRole.
- Specific permissions for the AWSLambdaBasicExecutionRole

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "logs:CreateLogGroup",
      "Resource": "arn:aws:logs:us-east-2:awsAccountNumber:*"
    },
    {
      "Effect": "Allow",
      "Action": ["logs:CreateLogStream", "logs:PutLogEvents"],
      "Resource": [
        "arn:aws:logs:us-east-2:awsAccountNumber:log-group:/aws/lambda/invoke-wau-audit-logs-glue-job:*"
      ]
    }
  ]
}
```

### S3

- Create a new S3 bucket with a folder named ***csv***.
- In order for the audit log CSV lambda to access the central S3 bucket, an [S3 access point](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-points-policies.html#access-points-delegating-control) must be created.
- The CSV lambda role's policy needs a resource entry for the access point as well. Currently, "*" is the only thing that seems to work. I have tried the access point's ARN and an *Access Denied* error is returned.

Bucket policy to delegate permissions to the access point
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "*"
            },
            "Action": "*",
            "Resource": [
                "arn:aws:s3:::sandbox-wau-audit-logs",
                "arn:aws:s3:::sandbox-wau-audit-logs/*"
            ],
            "Condition": {
                "StringEquals": {
                    "s3:DataAccessPointAccount": "502002958688"
                }
            }
        }
    ]
}
```

Access point policy
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::543706083199:role/platform-sandbox2-account-AuditLogLambdaRole-GL50V4JQSXMT"
            },
            "Action": [
                "s3:GetObject",
                "s3:PutObject"
            ],
            "Resource": [
                "arn:aws:s3:us-west-2:502002958688:accesspoint/sandbox-wau-audit-logs-access-point",
                "arn:aws:s3:us-west-2:502002958688:accesspoint/sandbox-wau-audit-logs-access-point/object/*"
            ]
        }
    ]
}
```
### Redshift Serverless Instance

#### ***Note: Redshift Serverless instances require at least 3 AZs. Ensure your VPC/subnets are configured appropriately or you will not be able to proceed with creating the instance.***

- https://docs.aws.amazon.com/redshift/latest/mgmt/serverless-workgroup-namespace.html
- Some discussion is probably needed here such that we can create a meaningful workgroup and namespace configuration.
  - The workgroup manages compute, networking, and security. It's also the level at which you connect via JDBC, etc.
  - The namespace manages the data.
- I used the default **_dev_** database but we need to be more deliberate with naming.
- For the poc environment, the workgroup configuration utilized the the VPC, security group, and subnets associated with the RDS VPC. For the sake of the Citrine environment, I assume it will be the platform-vpc but that remains to be seen.
- Create a wau_audit_logs, or something equally suitable, table in Redshift by using the create table from CSV option.
- There is an IAM role involved - AmazonRedshiftAllCommandsFullAccess policy at a minimum. I need to take a closer look. The role was created automatically during the configuration process.
- https://docs.aws.amazon.com/redshift/latest/gsg/serverless-first-time-setup.html
  - Permissions required to use Amazon Redshift Serverless

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "redshift-serverless.amazonaws.com",
          "redshift.amazonaws.com"
        ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

### Glue data catalog for the audit log file and Redshift table schema

- Create a single database that will contain the wau audit log file and Redshift table schemas.
- Create a Redshift connection.
  - I used a JDBC connection type, which can be gleaned from selecting the Redshift workgroup.
  - I used the username/password but a secret would be more appropriate.
- Create a crawler with two data sources defined for the csv and the Redshift table.
  - S3 data source:
    - Path: ensure the S3 data source path only includes the **_csv_** folder.
    - Subsequent crawler runs: Crawl all sub-folders.
  - Redshift data source:
    - JDBC
    - Connection: the Redshift connection created above.
    - The include path for the Redshift data source will be database/schema/table e.g. **_dev/public/wau_audit_logs_**
- Execute the crawler to create the necessary database tables in the Glue catalog.
- Verify the table schemas are created correctly.

### Glue Job

- Create a new Glue job.
  - Source node:
    - Node type: Amazon S3
    - S3 source type: Data Catalog table
    - Select the applicable database and table
  - Destination node:
    - Node type - Amazon Redshift
    - Select the applicable database and table
  - Job details tab:
    - IAM Role: Glue service role
    - Glue version: Glue 3.0 (If there are issues, try Glue version 2.0)
    - Language: Python 3
    - Worker type: decision point
    - Automatically scale the number of workers: check
    - Maximum number of workers: decision point
    - Generate job insights: check
    - Job bookmark: Enable
    - Flex execution: decision point
    - Number of retries: decision point. I have it set to 1 for the poc.
    - Advanced properties:
      - Max Concurrency = 1 for bookmarks.
      - see Error: A job is reprocessing data when job bookmarks are enabled in troubleshooting errors link below.
        - https://docs.aws.amazon.com/glue/latest/dg/monitor-continuations.html
        - https://docs.aws.amazon.com/glue/latest/dg/glue-troubleshooting-errors.html#error-job-bookmarks-reprocess-data
      - I left the remaining properties set to their default values.

### Glue Job Invocation Lambda

### Update: We no longer need this Lambda or the EventBridge trigger as we can schedule the Glue job directly.

- Select the Lambda IAM role created above or allow the role to be auto-generated.
- Code changes: The Glue job name if a different name is preferred.

```python
import json
import boto3

def lambda_handler(event, context):
   glueclient = boto3.client('glue')
   glueclient.start_job_run(JobName='populate-redshift-wau-audit-logs')
```

### Glue Job Invocation Lambda Trigger
- Configure an EventBridge (CloudWatch Events) trigger as a cron expression: ***cron(0 0 ? * * *)***