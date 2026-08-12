### AWS Enumeration
=======================================

Automatically enumerate AWS resources, IAM users, groups, roles, policies, and permissions, s3 bucket, lambda, ec2 using the configured AWS CLI profile.

The script uses `jq` to automatically extract AWS JSON fields.

sudo apt install jq

Before run the script, configure profile in the AWS CLI using below command.

aws configure --profile <Profile_Name>

### IAM Enumeration Usage
========================================

chmod +x aws_enum.sh

Then

./aws_enum.sh <Profile_Name>

Example: ./aws_enum.sh ctf
