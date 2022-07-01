# quicksight-poc

[Amazon QuickSight deployment models for cross-account and cross-Region access to Amazon Redshift and Amazon RDS](https://aws.amazon.com/blogs/big-data/amazon-quicksight-deployment-models-for-cross-account-and-cross-region-access-to-amazon-redshift-and-amazon-rds/)

_Apply Citrine-specific naming conventions for tags, etc._

## Prepare the QuickSight Environment

1. create a VPC and a subnet in the Region where your QuickSight account is deployed.

   ```powershell
   aws ec2 create-vpc \
     --cidr-block CIDR block different than where rds is deployed \
     --tag-specifications ResourceType=vpc,Tags=[{Key=Name,Value=QuickSightVPC}]
   ```

2. Create a subnet where QuickSight can deploy an ENI:

   ```powershell
   aws ec2 create-subnet \
     --vpc-id ID of the VPC you created above \
     --cidr-block subnet cidr block within your VPC range \
     --tag-specifications ResourceType=subnet,Tags=[{Key=Name,Value=QuickSightSubnet}]
   ```

3. create a security group and allow a self-reference for all TCP traffic from the VPC CIDR range:

   ```powershell 
   aws ec2 create-security-group \
     --group-name QuickSightSG \
     --description "QuickSight security group" \
     --vpc-id ID of the VPC you created above \
     --tag-specifications ResourceType=security-group,Tags=[{Key=Name,Value=QuickSightSG}]
   ```

4. create a route table and associate it to the subnet you created:

   ```powershell 
   aws ec2 create-route-table \
     --vpc-id ID of the VPC you created above \ 
     --tag-specifications ResourceType=route-table,Tags=[{Key=Name,Value=QuickSightRouteTable}]
   ```

   ```powershell 
   aws ec2 associate-route-table \
     --route-table-id id of route table created above \
     --subnet-id subnet id created above
   ```

### Now you configure QuickSight to create a VPC connection in the subnet you just created.

5. Sign in to the QuickSight console with administrator privileges.
6. Choose your profile icon and choose **Manage QuickSight**.
![QuickSight UI](https://d2908q01vomqb2.cloudfront.net/b6692ea5df920cad691c20319a6fffd7a4a766b8/2021/09/09/QS-ManageQuickisight-1024x515.png)
7. On the Manage QuickSight console, in the left panel, choose Manage VPC Connections.
8. Choose Add VPC Connection.
9. Provide the VPC ID, subnet ID, and security group ID you created earlier.
10. You can leave DNS resolver endpoints empty unless you have a private DNS deployment in the VPC.

You have now enabled QuickSight to access a subnet in your VPC. The following diagram shows the infrastructure you deployed.

![QucikSight VPC diagram](https://d2908q01vomqb2.cloudfront.net/b6692ea5df920cad691c20319a6fffd7a4a766b8/2021/09/10/QS-ENI-1.png)

## Set up the data source infrastructure

### VPC peering

**A peering request will need to be intiated from the QuickSight VPC to each of the RDS VPCs.**

[VPC peering limitations](https://docs.aws.amazon.com/vpc/latest/peering/vpc-peering-basics.html#vpc-peering-limitations)

#### using the AWS console

[Creating and accepting a VPC peering connection](https://docs.aws.amazon.com/vpc/latest/peering/create-vpc-peering-connection.html)

#### using the AWS CLI

1. creating the peering connection request

- [create-vpc-peering-connection](https://docs.aws.amazon.com/cli/latest/reference/ec2/create-vpc-peering-connection.html)

   ```powershell 
   aws ec2 create-vpc-peering-connection \
     --vpc-id your vpc id \
     --peer-vpc-id your peer vpc id \
     --peer-owner-id your peer owner id \
     --peer-region the peer region
   ```

2. accepting the peering connection request

- [accept-vpc-peering-connection](https://docs.aws.amazon.com/cli/latest/reference/ec2/accept-vpc-peering-connection.html)
   
   ```powershell 
   aws ec2 accept-vpc-peering-connection \
     --vpc-peering-connection-id VpcPeeringConnectionId from the create command response
   ```

3. modifying the peering connections to enable DNS resolution

- [modify-vpc-peering-connection-options](https://docs.aws.amazon.com/cli/latest/reference/ec2/modify-vpc-peering-connection-options.html)

  #### accepter - enable DNS resolution

   ```powershell 
   aws ec2 modify-vpc-peering-connection-options \
     --vpc-peering-connection-id VpcPeeringConnectionId from the accept command response \
     --accepter-peering-connection-options AllowDnsResolutionFromRemoteVpc=true
   ```

  #### requestor

   ```powershell
   aws ec2 modify-vpc-peering-connection-options \
     --vpc-peering-connection-id VpcPeeringConnectionId from the accept command response \
     --requester-peering-connection-options AllowDnsResolutionFromRemoteVpc=true
   ```

   If you encounter a **_Public Hostnames are disabled for: vpc-_** error, follow these steps to enable DNS hostnames for each VPC and then return to the modify-vpc-peering-connection-options commands above to enable DNS resolution
   [modify-vpc-attribute](https://awscli.amazonaws.com/v2/documentation/api/latest/reference/ec2/modify-vpc-attribute.html)

   ```powershell
   aws ec2 modify-vpc-attribute \
     --vpc-id vpc id \
     --enable-dns-hostnames
   ```

   [describe-vpc-attribute](https://awscli.amazonaws.com/v2/documentation/api/latest/reference/ec2/describe-vpc-attribute.html)

   ```powershell
   aws ec2 describe-vpc-attribute \
     --vpc-id vpc id \
     --attribute enableDnsHostnames
   ```

4. verify the peering connection settings

   [describe-vpc-peering-connection](https://awscli.amazonaws.com/v2/documentation/api/latest/reference/ec2/describe-vpc-peering-connections.html?highlight=peering)

   ```powershell 
   aws ec2 describe-vpc-peering-connections \
     --filters Name=status-code,Values=active
   ```
    - ensure the PeeringOptions object's AllowDnsResolutionFromRemoteVpc property is true for both the accepter and requester
    - you will have to change accounts to validate both properties
    - you can validate these settings in the console as well by going to VPC => Peering Connections, select each peering connection id and verify the settings on the DNS tab.    

5. update the route tables in both the QuickSight VPC and data source VPC to route network traffic between them

- from QuickSight => data source peering connection

   ```powershell 
   aws ec2 create-route \
     --route-table-id quicksight subnet route table id \
     --destination-cidr-block data source vpc cidr \
     --vpc-peering-connection-id the id of the peering you created above
   ```

- from RDS VPCs => QuickSight VPC

   ```powershell 
   aws ec2 create-route \
     --route-table-id data source subnet route table id \
     --destination-cidr-block quicksight vpc cidr \
     --vpc-peering-connection-id the id of the peering you created above
   ```

6. in the QuickSight AWS account, run the following command:

   ```powershell 
   aws ec2 authorize-security-group-ingress \
     --group-id quicksight security group \
     --ip-permissions IpProtocol=tcp,FromPort=0,ToPort=65535,IpRanges=[{CidrIp=data source subnet cidr}]
   ```

7. in the data source AWS account, run the following command

   ```powershell 
   aws ec2 authorize-security-group-ingress \
     --group-id data source security group \
     --ip-permissions IpProtocol=tcp,FromPort=0,ToPort=65535,IpRanges=[{CidrIp=quicksight subnet cidr}]
   ```

  ![VPC peering diagram](https://d2908q01vomqb2.cloudfront.net/b6692ea5df920cad691c20319a6fffd7a4a766b8/2021/09/10/QS-Peering-1.png)

## Connect QuickSight to the data source

Now that you have established the network link and configured both QuickSight and the data source to accept incoming and outgoing network traffic, you set up QuickSight to connect to the data source.

1. On the QuickSight console, choose Datasets in the navigation pane.
2. Choose **Add a dataset**.
3. Choose your database engine...PostgreSQL.
   Do not choose Amazon RDS or Amazon Redshift auto-discover.
4. For **Connection type**, choose the VPC connection you created.
5. Provide the necessary information about your database server.
6. Choose **Validate connection** button to make sure QuickSight can connect to the data source.
7. Choose **Create data source**.

![configure the data source](https://d2908q01vomqb2.cloudfront.net/b6692ea5df920cad691c20319a6fffd7a4a766b8/2021/09/09/QS-Add-Source-UI-1024x519.png)

8. Choose the database you want to use and select the table.

You’re now ready to build your dashboards and reports.

## AWS CLI named profiles

using the CLI against multiple AWS accounts can be cumbersome and time-consuming. named profiles can help.

[named profiles](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html)
[config and credential file settings](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html#cli-configure-files-settings)
