# quicksight-poc

[Deployment Model](https://aws.amazon.com/blogs/big-data/amazon-quicksight-deployment-models-for-cross-account-and-cross-region-access-to-amazon-redshift-and-amazon-rds/)

*CIDR blocks will differ*

## create quicksight vpc
- `aws ec2 create-vpc --cidr-block 172.32.0.0/16 --tag-specifications ResourceType=vpc,Tags=[{Key=Name,Value=QuicksightVPC}]`

## create quicksight subnet
- `aws ec2 create-subnet --vpc-id vpc-0d3024c96269fc7f6 --cidr-block 172.32.0.0/16 --tag-specifications ResourceType=subnet,Tags=[{Key=Name,Value=QuicksightSubnet}]`