#!/usr/bin/sh

accountId=`aws sts get-caller-identity |grep Account | awk -F':' '{print $2}' | sed 's/"//g;s/,//g;s/ //g'`
echo "$accountId"
sleep 1
region=`ec2-metadata -z | sed 's/.$//' | awk -F': ' '{print $2}'`
echo "$region"
sleep 1
instanceId=`ec2-metadata | grep instance-id |  awk -F': ' '{print $2}'| sed 's/,//g'`
echo "$instanceId"
sleep 1
vpcId=`aws ec2 describe-instances --instance-id ${instanceId} --region ${region} | grep -i VpcId | head -1 | awk -F': "' '{print $2}' | sed 's/"//g;s/,//g'`
echo "$vpcId"
sleep 1
cidrBlock=`aws ec2 describe-vpcs --vpc-id ${vpcId} --region ${region} | grep 'CidrBlock":' | head -1 | awk -F': "' '{print $2}' | sed 's/"//g;s/,//g'`
echo "$cidrBlock"
sleep 1
subnetIds=`aws ec2 describe-subnets --region ${region} --filter "Name=vpc-id,Values=${vpcId}"  | grep SubnetId | tr -d '\n' | sed 's/"SubnetId": //g;s/ //g;s/.$//;s/","/,/g;s/"//g'`
echo "$subnetIds"
subnetIdsyml=`aws ec2 describe-subnets --region ${region} --filter "Name=vpc-id,Values=${vpcId}"  | grep SubnetId | tr -d '\n' | sed 's/"SubnetId": //g;s/ //g;s/.$//;s/","/,/g;s/"//g;s/^/- /g;s/,/##########- /g'`
echo "$subnetIdsyml"
sleep 1
securityGroup=`aws ec2 describe-security-groups --region ${region} --filter "Name=tag:Name,Values=elklogging" | grep GroupId | awk -F': "' '{print $2}' | sed 's/"//g;s/,//g'`
echo "$securityGroup"
sleep 1
#`rm -rf functionbeat`
sleep 1
#`git clone https://github.com/smasharpit/functionbeat.git`
sleep 1
`sed -i "s,DEFAULTVPCCIDR,${cidrBlock},g" functionbeat/securitygroup.json`
`sed -i "s/DEFAULTVPCID/${vpcId}/g" functionbeat/securitygroup.json`
sleep 1
S3_CHECK=$(aws s3 ls "s3://elklogs-${accountId}" 2>&1)
if [ $? != 0 ]
then
  NO_BUCKET_CHECK=$(echo $S3_CHECK | grep -c 'NoSuchBucket') 
  if [ $NO_BUCKET_CHECK = 1 ]; then
    `aws s3api create-bucket --bucket elklogs-${accountId} --region ${region}  --create-bucket-configuration LocationConstraint=${region}  --acl private`
  fi
fi
sleep 2
`aws s3 cp --quiet --ignore-glacier-warnings --only-show-errors functionbeat/securitygroup.json s3://elklogs-${accountId}/securitygroup.json`
sleep 2
`sed -i "s/REGION/${region}/g" functionbeat/functionbeat.yml`
`sed -i "s/ACCOUNTID/${accountId}/g" functionbeat/functionbeat.yml`
`sed -i "s/SGROUP/${securityGroup}/g" functionbeat/functionbeat.yml`
`sed -i "s/SUBNETIDS/${subnetIdsyml}/g" functionbeat/functionbeat.yml`
`sed -i "s,##########,\n          ,g" functionbeat/functionbeat.yml`
`dos2unix functionbeat/functionbeat.yml`
`zip --quiet -j functionbeat/package-aws.zip functionbeat/functionbeat.yml`
sleep 2
`sed -i "s/DEFAULTSUBNETS/${subnetIds}/g" functionbeat/elklogging.json`
`sed -i "s/DEFAULTSECURITYGROUP/${securityGroup}/g" functionbeat/elklogging.json`
sleep 2
#`aws s3 cp --quiet --ignore-glacier-warnings --only-show-errors functionbeat/package-aws.zip s3://elklogs-${accountId}/package-aws.zip`