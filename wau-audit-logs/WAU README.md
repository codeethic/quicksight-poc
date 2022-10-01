# Citrine - WAU Audit Log Analytics

## Objective

- Aggregate all wau audit log files into a centralized S3 bucket in the same region/account as Glue/Redshift.
- Invoke a Glue job to process each of the audit log files and load the data into Redshift for analytics.

## Required Changes to the Existing Process

- Add the customer field to the csv.
- Write the WAU audit log files, generated for each customer, to a new centralized S3 bucket in the same region/account as Glue and Redshift. [AuditLogCsvLambda python](https://github.com/codeethic/quicksight-poc/blob/main/wau-audit-logs/lambda-csv-writer.md)
- Add a new environment variable to the CSV Lambda that points to the central S3 bucket's access point called AUDIT_LOGS_ARTIFACT_ACCESS_POINT. The Lambda's python use this variable.
- Update the Lambda's IAM role policy with a resource entry for the access point. Currently, "*" is the only thing that seems to work. I have tried the access point's ARN and an *Access Denied* error is returned.

## Configuration

### Central S3 Bucket

- Create a new S3 bucket with a folder named ***csv***.
- In order for the audit log CSV lambda to access the central S3 bucket, an [S3 access point](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-points-policies.html#access-points-delegating-control) must be created.

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

### Create new analytics-vpc
- This may require a service quota limit increase which should only take a few minutes.
- Must have at least 3 subnets/AZs to meet the minimum Redshift Serverless requirements.
- Example subnet config
  - VPC CIDR: 172.33.0.0/16
  - Subnets:
    - analytics-vpc-subnet-az1: 172.33.0.0/20
    - analytics-vpc-subnet-az2: 172.33.16.0/20
    - analytics-vpc-subnet-az3: 172.33.32.0/20

- Configure the VPC's S3 gateway endpoint. Glue will require this for the S3 crawler.
  - analytics-vpc-s3-gateway-endpoint
    - ensure it's a gateway endpoint and configured in the appropriate region.

### Redshift Serverless Instance

#### ***Note: Redshift Serverless instances require at least 3 AZs. Ensure your VPC/subnets are configured appropriately or you will not be able to proceed with creating the instance.***

- https://docs.aws.amazon.com/redshift/latest/mgmt/serverless-workgroup-namespace.html

#### Create the Workgroup

- The workgroup manages compute, networking, and security. It's also the level at which you connect via JDBC, etc.
- The namespace manages the data.
- Provide a meaningful workgroup name.
- Use the analytics-vpc created about and its associated security group when configuring the workgroup.
- Click the Next button to create the namespace for the workgroup.
- Provide a meaningful name.
- The default **_dev_** database name can not be changed.
- Click customize admin user credentials
  - username: admin
  - password: generate or enter but retain this information in an appropriate location
- [Permissions](https://docs.aws.amazon.com/redshift/latest/gsg/serverless-first-time-setup.html) 
  - Click the Manage IAM role button
  - Select Create IAM Role or create your own role and enure to apply the AmazonRedshiftAllCommandsFullAccess policy.
    - IAM role on Sandbox: citrine-analytics-redshift with the AmazonRedshiftAllCommandsFullAccess policy.
    - Permissions required to use Amazon Redshift Serverless (check the link above to see whether this is enough or just let Redshift create the IAM role).

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

#### Create the database table

- Create a wau_audit_logs, or something equally suitable, table in Redshift **_dev_** database by using the create table from CSV option. An updated CSV with the unique_identifier and customer columns will be required to ensure the table's schema is accurate.

### Glue data catalog for the audit log file and Redshift table schema

- Create a single database that will contain the wau audit log file and Redshift table schemas e.g. wau_audit_logs.
- Create a Redshift connection.
  - I used a JDBC connection type, which can be gleaned from selecting the Redshift workgroup.
  - I used the username/password but a secret would be more appropriate.
- Create a crawler with two data sources defined for the csv and the Redshift table.
  - **Note:** Ensure the CSV and the Redshift table's schema are the latest so that the crawler creates the most current Glue data catalog schemas. We can always re-run the crawler but it's better to get it right the first time.
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

      - Create a schedule for the Glue job on the Schedule tag e.g. Daily at midnight.

### Glue Job Invocation Lambda

### **Update**: We no longer need this Lambda or the EventBridge trigger as we can schedule the Glue job directly.

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