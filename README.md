# quicksight-poc

[Deployment Model](https://aws.amazon.com/blogs/big-data/amazon-quicksight-deployment-models-for-cross-account-and-cross-region-access-to-amazon-redshift-and-amazon-rds/)

_IDs and CIDR blocks will differ_

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

### VPC peering connections

[VPC peering limitations](https://docs.aws.amazon.com/vpc/latest/peering/vpc-peering-basics.html#vpc-peering-limitations)

#### using the AWS console

[Creating and accepting a VPC peering connection](https://docs.aws.amazon.com/vpc/latest/peering/create-vpc-peering-connection.html)

#### using the AWS CLI

1. creating the peering connection request

- [create-vpc-peering-connection](https://docs.aws.amazon.com/cli/latest/reference/ec2/create-vpc-peering-connection.html)
- `aws ec2 create-vpc-peering-connection --vpc-id *your vpc id* --peer-vpc-id *your peer vpc id* --peer-owner-id *your peer owner id* --peer-region *the peer region*`

2. accepting the peering connection request

- [accept-vpc-peering-connection](https://docs.aws.amazon.com/cli/latest/reference/ec2/accept-vpc-peering-connection.html)
- `aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id *VpcPeeringConnectionId from the create command response*`

3. modifying the peering connections to enable DNS resolution

- [modify-vpc-peering-connection-options](https://docs.aws.amazon.com/cli/latest/reference/ec2/modify-vpc-peering-connection-options.html)

#### accepter
- ``aws ec2 modify-vpc-peering-connection-options --vpc-peering-connection-id *VpcPeeringConnectionId from the accept command response* --accepter-peering-connection-options AllowDnsResolutionFromRemoteVpc=true``

#### requestor
- `aws ec2 modify-vpc-peering-connection-options --vpc-peering-connection-id *VpcPeeringConnectionId from the accept command response* --requester-peering-connection-options AllowDnsResolutionFromRemoteVpc=true`

If you encounter a _Public Hostnames are disabled for: vpc-_, follow these steps to enable DNS hostnames for each VPC
[modify-vpc-attribute](https://awscli.amazonaws.com/v2/documentation/api/latest/reference/ec2/modify-vpc-attribute.html)
- `aws ec2 modify-vpc-attribute --vpc-id *your vpc id* --enable-dns-hostnames`

[describe-vpc-attribute](https://awscli.amazonaws.com/v2/documentation/api/latest/reference/ec2/describe-vpc-attribute.html)
- 'aws ec2 describe-vpc-attribute --vpc-id *your vpc id* --attribute enableDnsHostnames

4. verify the peering connection settings

[describe-vpc-peering-connection](https://awscli.amazonaws.com/v2/documentation/api/latest/reference/ec2/describe-vpc-peering-connections.html?highlight=peering)
- `aws ec2 describe-vpc-peering-connections --filters Name=status-code,Values=active`
- ensure the PeeringOptions object's AllowDnsResolutionFromRemoteVpc property is true for both the accepter and requester
- you will have to change accounts to validate both properties
- you can validate these settings in the console as well by going to VPC => Peering Connections, select each peering connection id and verify the settings on the DNS tab.

5. update the route tables in both the QuickSight VPC and data source VPC to route network traffic between them

## isseues here with overlapping CIDRs which is probably going to invalidate the VPC peering approach...waiting on clarification

- from QuickSight => data source peering connection
- `aws ec2 create-route --route-table-id *amazon quicksight subnet route table id* --destination-cidr-block *data source vpc cidr* --vpc-peering-connection-id *the id of the peering you created above*`

- from RDS VPCs => QuickSight VPC
- `aws ec2 create-route --route-table-id *data source subnet route table id* --destination-cidr-block *quicksight vpc cidr* --vpc-peering-connection-id *the id of the peering you created above*`


6. in the QuickSight AWS account, run the following command:
- `aws ec2 authorize-security-group-ingress --group-id *quicksight security group* --ip-permissions IpProtocol=tcp,FromPort=0,ToPort=65535,IpRanges=[{CidrIp=*data source subnet CIDR*}]`


7. in the data source AWS account, run the following command
- `aws ec2 authorize-security-group-ingress --group-id *data source security group* --ip-permissions IpProtocol=tcp,FromPort=0,ToPort=65535,IpRanges=[{CidrIp=*quicksight subnet CIDR*}]`

### End VPC peering connections

## Connect QuickSight to the data source

## AWS CLI named profiles
using the CLI against multiple AWS accounts can be cumbersome and time-consuming. named profiles can help.

[named profiles](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html)
[config and credential file settings](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html#cli-configure-files-settings)