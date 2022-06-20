# AWS QuickSight PoC High-level Spec

## Objective: 
Proof of concept to demonstrate how QuickSight can access an AWS RDS PostgreSQL database hosted in another AWS account.

## Deliverables:
md in the root of the repo that documents the process e.g. AWS console actions, AWS CLI commands, etc. such that Citrine can implement their final solution.
Any relevant automation scripts will be written in Python, placed in the repo, and provided to Citrine.

## Solution Approach:
[Deployment Model](https://aws.amazon.com/blogs/big-data/amazon-quicksight-deployment-models-for-cross-account-and-cross-region-access-to-amazon-redshift-and-amazon-rds/)

- Use Code Ethic GitHub repo for artifacts
- Host AWS RDS/PostgreSQL database instance in Code Ethic’s AWS account
  - Create two RDS instance and host a database in each
  - Populate the databases with test data
- Configure RDS instance for access
  - VPC peering preferred, transit gateway, something else?
- Create AWS QuickSight instance in Chad’s AWS account
- Create an RDS instance and host a database
- Configure QuickSight RDS connection to RDS instance(s) in Code Ethic’s account
  - [Supported Datasources](https://docs.aws.amazon.com/quicksight/latest/user/supported-data-sources.html)
- Create a basic QuickSight table that displays data from all PostgreSQL databases across both accounts and instances

## Assumptions:
- No CloudFormation or Terraform…no IaC
- Use of Code Ethic’s GitHub repository
  - Josh to create a repo and provide Chad access - Done
- Chad will have access to Code Ethic’s AWS account via an IAM user with the necessary permissions to perform the required actions.
  - Josh will create AWS IAM user
  - Josh to provide IAM user credentials
  - Enable MFA 
- Citrine has/will have a QuickSight Enterprise account. This will be required in order to connect QuickSight to a VPC—through an Elastic Network Interface (ENI)—and keep network traffic private within the AWS network

## Questions:
- Does Citrine have Amazon RDS or Amazon Redshift in the same Region and do they use cross-account resource sharing for their VPCs? Different accounts/regions
- Does Citrine use AWS Organizations? Yes
- Does Citrine use VPC peering or a Transit Gateway to communicate between existing VPCs or neither?
- Does Citrine use more than one region? Yes
