# quicksight-poc

[Deployment Model](https://aws.amazon.com/blogs/big-data/amazon-quicksight-deployment-models-for-cross-account-and-cross-region-access-to-amazon-redshift-and-amazon-rds/)

*IDs and CIDR blocks will differ*

1. create a VPC and a subnet in the Region where your QuickSight account is deployed. See the following code:
- `aws ec2 create-vpc --cidr-block 172.32.0.0/16 --tag-specifications ResourceType=vpc,Tags=[{Key=Name,Value=QuicksightVPC}]`

2. Create a subnet where QuickSight can deploy an ENI:
- `aws ec2 create-subnet --vpc-id vpc-0d3024c96269fc7f6 --cidr-block 172.32.0.0/16 --tag-specifications ResourceType=subnet,Tags=[{Key=Name,Value=QuicksightSubnet}]`

3. create a security group and allow a self-reference for all TCP traffic from the VPC CIDR range:
- `aws ec2 create-security-group --group-name QuicksightSG --description "Quicksight security group" --vpc-id vpc-0d3024c96269fc7f6 --tag-specifications ResourceType=security-group,Tags=[{Key=Name,Value=QuicksightSG}]`

4. create a route table and associate it to the subnet you created:
- `aws ec2 create-route-table --vpc-id vpc-0d3024c96269fc7f6 --tag-specifications ResourceType=route-table,Tags=[{Key=Name,Value=QuicksightRouteTable}]`

- `aws ec2 associate-route-table --route-table-id rtb-016df04481f5e7ed8 --subnet-id subnet-0fce1838451b5dcff`

## Now you configure QuickSight to create a VPC connection in the subnet you just created.

5. Sign in to the QuickSight console with administrator privileges.
6. Choose your profile icon and choose **Manage QuickSight**.
7. On the Manage QuickSight console, in the left panel, choose Manage VPC Connections.
8. Choose Add VPC Connection.
9. Provide the VPC ID, subnet ID, and security group ID you created earlier.
10. You can leave DNS resolver endpoints empty unless you have a private DNS deployment in the VPC.

## set up the data source infrastructure

### VPC peering

