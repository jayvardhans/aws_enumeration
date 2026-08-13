### AWS Enumeration
=======================================

Automatically enumerate AWS resources, IAM users, groups, roles, policies, and permissions, s3 bucket, lambda, ec2 using the configured AWS CLI profile.

The script uses `jq` to automatically extract AWS JSON fields.

`sudo apt install jq`

Before run the script, configure profile in the AWS CLI using below command.

`aws configure --profile <Profile_Name>`

### IAM Enumeration Usage
========================================

`chmod +x aws_enum.sh`

Then

`./aws_enum.sh <Profile_Name>`

Example: `./aws_enum.sh ctf`

### Check S3 Bucket
==========================================

Script will checks anonymous listing s3 bucket, downloads the first small object it finds, and test anonymous write access with an empty bucket_writable.txt, and saves the results to out.json.

###### Usage
==========================================

For Linux: `chmod +x s3_check.py`

Run it with the bucket name:

`./s3_check.py <bucket_name>`

For windows: `python s3_check.py my-ctf-bucket`

