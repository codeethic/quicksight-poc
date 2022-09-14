# Citrine - WAU Audit Log Analytics

## Objective 
 - Aggregate all wau audit log files into a centralized S3 bucket in the same region/account as Glue/Redshift.
 - Invoke a Glue job to process each of the audit log files and load the data into Redshift for analytics.


## Required Changes to the Existing Process
 - Add the customer field to the csv.
 - Copy the WAU audit log files, generated for each customer, to a new centralized S3 bucket in the same region/account as Glue and Redshift.
 - Write a file to a new object/folder, in the centralized S3 bucket when the audit log aggregation process is complete. The ObjectCreated event generated by this file will trigger the Glue job.


## Configuration

### IAM Role
 - Create a new IAM role that the lambda function can assume, unless one exists that should be used.
 - Required policies: AWSLambdaBasicExecutionRole, AWSGlueServiceRole.

### S3

- Create a new S3 bucket with two folders, one named csv and the other complete (or something else that indicates the audit log file aggregation process is finished).
- **Having the two folders allows us to target the csv folder specifically in our crawler's S3 data source configuration so that we don't create a data catalog table for our completed file**

### Redshift Serverless Instance

- https://docs.aws.amazon.com/redshift/latest/mgmt/serverless-workgroup-namespace.html
- Some discussion is probably needed here such that we can create a meaningful workgroup and namespace configuration.
- I used the default ***dev*** database but we need to be more deliberate with naming.
- For the poc environment, the workgroup configuration utilized the the VPC, security group, and subnets associated with the RDS VPC. For the sake of the Citrine environment, I assume it will be the platform-vpc but that remains to be seen.
- Create a wau_audit_logs, or something equally suitable, table in Redshift by using the create table from CSV option.
- There is an IAM role involved - AmazonRedshiftAllCommandsFullAccess policy at a minimum. I need to take a closer look. The role was created automatically during the configuration process.
- https://docs.aws.amazon.com/redshift/latest/gsg/serverless-first-time-setup.html
    - Permissions required to use Amazon Redshift Serverless
````json
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
````

### Glue data catalog for the audit log file and Redshift table schema

- Create a single database that will contain the wau audit log file and Redshift table schemas.
 - Create a Redshift connection.
     - I used a JDBC connection type, which can be gleaned from selecting the Redshift workgroup.
     - I used the username/password but a secret would be more appropriate.
 - Create a crawler with two data sources defined for the csv and the Redshift table.
     - S3 data source:
         - Path: ensure the S3 data source path only includes the ***csv*** folder. We don't need a table generated in the catalog for the ***complete*** folder.
         - Subsequent crawler runs: Crawl all sub-folders.
     - Redshift data source:
         - JDBC
         - Connection: the Redshift connection created above.
         - The include path for the Redshift data source will be database/schema/table e.g. ***dev/public/wau_audit_logs***
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

### Lambda

 - Select the lambda IAM role created above.
 - Code changes: update the name of the file indicating the aggregation process is complete and the Glue job name. probably shouldn't be hardcoded. 
 ````python
import json
import boto3

def lambda_handler(event, context):
    nexttask = event["Records"][0]["s3"]["object"]["key"]
    glueclient = boto3.client('glue')
    if nexttask == 'token/populate-redshift-wau-audit-logs.txt':
        glueclient.start_job_run(JobName='populate-redshift-wau-audit-logs')
 ````
- Ensure the JobName parameter's value is accurate.
- Configure the lambda S3 trigger.
    - Bucket: the bucket created above.
    - Event type: PUT, POST or All object created events.
    - Prefix: the folder name created above to indicate the file aggregation process is complete.
    - Suffix: dependent upon the file type written to the process complete folder. needs to match the code above.

 ### The multiple S3 ObjectCreated Events Issue
  
This process aggregates WAU audit log files, from all customers, to a cental S3 bucket for ETL processing via a Glue job. Each file added to the S3 bucket generates an ObjectCreated event. Each event invokes the Glue job. This results in concurrent job execution which causes a failure due to the max concurrency value of 1 which is required to support Glue job bookmarks as cited above.
Furthermore, even if we could increase the mx concurrency value, each event causes the Glue job to process ALL of the files as there are no bookmarks to prevent it from occurring. Therefore, the process consumes all the files for each event and we reprocess the same data multiple times.

To work around this, the additional S3 folder, called complete above, was added to the S3 bucket. This allows the file aggregation Lambda to add a single file to that folder, when all customer WAU audit log files have been copied to the centralized S3 bucket, ensuring a single ObjectCreated event is published which invokes the Glue job once and it processes all of the new files.

Note: if a file with the same name as an existing file is copied to S3, the last modified time will change and that file will be processed again on a subsequent Glue job invocation.


  - https://www.youtube.com/watch?v=UBhG_UMuFEo