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
`sed -i "s,DEFAULTVPCCIDR,${cidrBlock},g" functionbeat/securitygroup.json`
`sed -i "s/DEFAULTVPCID/${vpcId}/g" functionbeat/securitygroup.json`
sleep 1
echo "checking bucket filelkintegration-${accountId} existance in ${region}"
S3_CHECK=$(aws s3 ls "s3://filelkintegration-${accountId}" 2>&1)
if [ $? != 0 ]
then
  NO_BUCKET_CHECK=$(echo $S3_CHECK | grep -c 'NoSuchBucket')
  if [ $NO_BUCKET_CHECK = 1 ]; then
    echo "bucket filelkintegration-${accountId} does not exist in ${region}"
    echo "creating bucket filelkintegration-${accountId} in ${region}"
    s3bucket=`aws s3api create-bucket --bucket filelkintegration-${accountId} --region ${region}  --create-bucket-configuration LocationConstraint=${region}  --acl private`
    echo "created bucket filelkintegration-${accountId} in ${region}"
    echo "$s3bucket"
    s3bucketblockpublic=`aws s3api put-public-access-block --bucket filelkintegration-${accountId} --region ${region} --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"`
    echo "blocking public access of S3 bucket"
    echo "$s3bucketblockpublic"
  fi
fi
sleep 2
`aws s3 cp --quiet --ignore-glacier-warnings --only-show-errors functionbeat/securitygroup.json s3://filelkintegration-${accountId}/securitygroup.json`
sleep 2
sgStackName="elklogging-securitygroup"
echo "$sgStackName"
SGSTACK_CHECK=$(aws cloudformation describe-stacks --stack-name ${sgStackName} --region ${region} --query Stacks[0].StackStatus 2>&1)
if [ $? == 0 ]
then
  echo "coming here"
  SGSTACK=$(echo $SGSTACK_CHECK | grep -c 'CREATE_COMPLETE') 
  if [ $SGSTACK = 1 ]; then
    echo "Stack ${sgStackName} exists, attempting update..."
    validateTemplate=`aws cloudformation validate-template --template-url https://s3.amazonaws.com/filelkintegration-${accountId}/securitygroup.json  --region ${region}`
    echo "$validateTemplate"
    stackupdate=`aws cloudformation update-stack --stack-name ${sgStackName} --template-url https://s3.amazonaws.com/filelkintegration-${accountId}/securitygroup.json --region ${region}  2>&1`
    echo "$stackupdate"
    SGSTACKUPDATE=$(echo $stackupdate | grep -c 'No updates are to be performed') 
    if [ $SGSTACKUPDATE = 1 ]; then
      echo "Security Group Stack ${sgStackName} is already Update to date"
    else
      waitstackUpdate=`aws cloudformation wait stack-create-complete --stack-name ${sgStackName} --region ${region}`
      echo "$waitstackUpdate"
      updatestackResources=`aws cloudformation describe-stack-events --stack-name ${sgStackName} --query 'StackEvents[].[{Resource:LogicalResourceId,Status:ResourceStatus,Reason:ResourceStatusReason}]' --output table --region ${region}`
      echo "$updatestackResources"
    fi
  else
    echo "Creating ${sgStackName} Stack"
    validateTemplate=`aws cloudformation validate-template --template-url https://s3.amazonaws.com/filelkintegration-${accountId}/securitygroup.json  --region ${region}`
    echo "$validateTemplate"
    createStack=`aws cloudformation create-stack --stack-name ${sgStackName} --template-url https://s3.amazonaws.com/filelkintegration-${accountId}/securitygroup.json --region ${region} 2>&1`
		echo "$createStack"
    SGSTACKCREATE=$(echo $createStack | grep -c 'already exists') 
    if [ $SGSTACKCREATE = 1 ]; then
      echo "Stack is already Created"
    else    
      waitstackCreate=`aws cloudformation wait stack-create-complete --stack-name ${sgStackName} --region ${region}`
		  echo "$waitstackCreate"
      trackStackResources=`aws cloudformation describe-stack-events --stack-name ${sgStackName} --query 'StackEvents[].[{Resource:LogicalResourceId,Status:ResourceStatus,Reason:ResourceStatusReason}]' --output table --region ${region}`
      echo "$trackStackResources"
      SGSTACKCREATEFAILED=$(echo $trackStackResources | grep -c 'CREATE_FAILED')
      if [ $SGSTACKCREATEFAILED = 1 ]; then
        echo "SECURITY GROUP STACK CREATION FAILED.. DELETING ${sgStackName} stack"
        deleteSGstack=`aws cloudformation delete-stack --stack-name ${sgStackName} --region ${region}`
        echo "${sgStackName} deleting..."
        echo "$deleteSGstack"
        deleteSGstack=`aws cloudformation wait stack-delete-complete --stack-name ${sgStackName} --region ${region}`
        echo "${sgStackName} deleted"
        echo "$deleteSGstack"
      fi
    fi
  fi
else
    echo "Creating ${sgStackName} Stack"
    validateTemplate=`aws cloudformation validate-template --template-url https://s3.amazonaws.com/filelkintegration-${accountId}/securitygroup.json  --region ${region}`
    echo "$validateTemplate"
    createStack=`aws cloudformation create-stack --stack-name ${sgStackName} --template-url https://s3.amazonaws.com/filelkintegration-${accountId}/securitygroup.json --region ${region} 2>&1`
		echo "$createStack"
    SGSTACKCREATE=$(echo $createStack | grep -c 'already exists') 
    if [ $SGSTACKCREATE = 1 ]; then
      echo "Stack is already Created"
    else    
      waitstackCreate=`aws cloudformation wait stack-create-complete --stack-name ${sgStackName} --region ${region}`
		  echo "$waitstackCreate"
      trackStackResources=`aws cloudformation describe-stack-events --stack-name ${sgStackName} --query 'StackEvents[].[{Resource:LogicalResourceId,Status:ResourceStatus,Reason:ResourceStatusReason}]' --output table --region ${region}`
      echo "$trackStackResources"
      SGSTACKCREATEFAILED=$(echo $trackStackResources | grep -c 'CREATE_FAILED')
      if [ $SGSTACKCREATEFAILED = 1 ]; then
        echo "SECURITY GROUP STACK CREATION FAILED.. DELETING ${sgStackName} stack"
        deleteSGstack=`aws cloudformation delete-stack --stack-name ${sgStackName} --region ${region}`
        echo "${sgStackName} deleting..."
        echo "$deleteSGstack"
        deleteSGstack=`aws cloudformation wait stack-delete-complete --stack-name ${sgStackName} --region ${region}`
        echo "${sgStackName} deleted"
        echo "$deleteSGstack"
      fi
    fi
fi
securityGroup=`aws ec2 describe-security-groups --region ${region} --filter "Name=tag:Name,Values=elklogging" | grep GroupId | awk -F': "' '{print $2}' | sed 's/"//g;s/,//g'`
echo "$securityGroup"
SGSCHECK=$(echo $securityGroup | grep -c 'sg') 
if [ $SGSCHECK = 1 ]; then
  `sed -i "s/SGROUP/${securityGroup}/g" functionbeat/functionbeat.yml`
  `sed -i "s/REGION/${region}/g" functionbeat/functionbeat.yml`
  `sed -i "s/ACCOUNTID/${accountId}/g" functionbeat/functionbeat.yml`
  `sed -i "s/SUBNETIDS/${subnetIdsyml}/g" functionbeat/functionbeat.yml`
  `sed -i "s,##########,\n          ,g" functionbeat/functionbeat.yml`
  `dos2unix functionbeat/functionbeat.yml`
  `zip --quiet -j functionbeat/package-aws.zip functionbeat/functionbeat.yml`
  sleep 2
  `sed -i "s/DEFAULTSUBNETS/${subnetIds}/g" functionbeat/elklogging.json`
  `sed -i "s/DEFAULTSECURITYGROUP/${securityGroup}/g" functionbeat/elklogging.json`
  sleep 2
  `aws s3 cp --quiet --ignore-glacier-warnings --only-show-errors functionbeat/package-aws.zip s3://filelkintegration-${accountId}/package-aws.zip`
  `aws s3 cp --quiet --ignore-glacier-warnings --only-show-errors functionbeat/elklogging.json s3://filelkintegration-${accountId}/elklogging.json`
  elkStackName="elklogging-elkintegration"
  echo "$elkStackName"
  ELKSTACK_CHECK=$(aws cloudformation describe-stacks --stack-name ${elkStackName} --region ${region} --query Stacks[0].StackStatus 2>&1)
  if [ $? == 0 ]
  then
    echo "coming here"
    SGSTACK=$(echo $ELKSTACK_CHECK | grep -c 'CREATE_COMPLETE') 
    if [ $SGSTACK = 1 ]; then
      echo "Stack ${elkStackName} exists, attempting update..."
      validateTemplate=`aws cloudformation validate-template --template-url https://s3.amazonaws.com/filelkintegration-${accountId}/elklogging.json  --region ${region}`
      echo "$validateTemplate"
      stackupdate=`aws cloudformation update-stack --stack-name ${elkStackName} --template-url https://s3.amazonaws.com/filelkintegration-${accountId}/elklogging.json --region ${region}  2>&1`
      echo "$stackupdate"
      ELKSTACKUPDATE=$(echo $stackupdate | grep -c 'No updates are to be performed') 
      if [ $ELKSTACKUPDATE = 1 ]; then
        echo "Stack ${elkStackName} is already Update to date"
      else
        waitstackUpdate=`aws cloudformation wait stack-create-complete --stack-name ${elkStackName} --region ${region}`
        echo "$waitstackUpdate"
        updatestackResources=`aws cloudformation describe-stack-events --stack-name ${elkStackName} --query 'StackEvents[].[{Resource:LogicalResourceId,Status:ResourceStatus,Reason:ResourceStatusReason}]' --output table --region ${region}`
        echo "$updatestackResources"
      fi
    else
      echo "Creating ${elkStackName} Stack"
      validateTemplate=`aws cloudformation validate-template --template-url https://s3.amazonaws.com/filelkintegration-${accountId}/elklogging.json  --region ${region}`
      echo "$validateTemplate"
      createStack=`aws cloudformation create-stack --stack-name ${elkStackName} --template-url https://s3.amazonaws.com/filelkintegration-${accountId}/elklogging.json --region ${region} 2>&1`
      echo "$createStack"
      ELKSTACKCREATE=$(echo $createStack | grep -c 'already exists') 
      if [ $ELKSTACKCREATE = 1 ]; then
        echo "Stack is already Created"
      else    
        waitstackCreate=`aws cloudformation wait stack-create-complete --stack-name ${elkStackName} --region ${region}`
        echo "$waitstackCreate"
        trackStackResources=`aws cloudformation describe-stack-events --stack-name ${elkStackName} --query 'StackEvents[].[{Resource:LogicalResourceId,Status:ResourceStatus,Reason:ResourceStatusReason}]' --output table --region ${region}`
        echo "$trackStackResources"
        ELKSTACKCREATEFAILED=$(echo $trackStackResources | grep -c 'CREATE_FAILED') 
        if [ $ELKSTACKCREATEFAILED = 1 ]; then
          echo "ELK STACK CREATION FAILED.. DELETING ${elkStackName} stack"
          deletestack=`aws cloudformation delete-stack --stack-name ${elkStackName} --region ${region}`
          echo "${elkStackName} deleting..."
          echo "$deletestack"
          deleteStatus=`aws cloudformation wait stack-delete-complete --stack-name ${elkStackName} --region ${region}`
          echo "${elkStackName} deleted"
          echo "$deleteStatus"
        fi
      fi
    fi
  else
      echo "Creating ${elkStackName} Stack"
      validateTemplate=`aws cloudformation validate-template --template-url https://s3.amazonaws.com/filelkintegration-${accountId}/elklogging.json  --region ${region}`
      echo "$validateTemplate"
      createStack=`aws cloudformation create-stack --stack-name ${elkStackName} --template-url https://s3.amazonaws.com/filelkintegration-${accountId}/elklogging.json --capabilities CAPABILITY_NAMED_IAM --region ${region} 2>&1`
      echo "$createStack"
      ELKSTACKCREATE=$(echo $createStack | grep -c 'already exists') 
      if [ $ELKSTACKCREATE = 1 ]; then
        echo "Stack is already Created"
      else    
        waitstackCreate=`aws cloudformation wait stack-create-complete --stack-name ${elkStackName} --region ${region}`
      echo "$waitstackCreate"
        trackStackResources=`aws cloudformation describe-stack-events --stack-name ${elkStackName} --query 'StackEvents[].[{Resource:LogicalResourceId,Status:ResourceStatus,Reason:ResourceStatusReason}]' --output table --region ${region}`
        echo "$trackStackResources"
        ELKSTACKCREATEFAILED=$(echo $trackStackResources | grep -c 'CREATE_FAILED') 
        if [ $ELKSTACKCREATEFAILED = 1 ]; then
          echo "ELK STACK CREATION FAILED.. DELETING ${elkStackName} stack"
          deletestack=`aws cloudformation delete-stack --stack-name ${elkStackName} --region ${region}`
          echo "${elkStackName} deleting..."
          echo "$deletestack"
          deleteStatus=`aws cloudformation wait stack-delete-complete --stack-name ${elkStackName} --region ${region}`
          echo "${elkStackName} deleted"
          echo "$deleteStatus"
          echo "DELETING Security Group Stack ${sgStackName} stack"
          deletestack=`aws cloudformation delete-stack --stack-name ${sgStackName} --region ${region}`
          echo "${sgStackName} deleting..."
          echo "$deletestack"
          deleteStatus=`aws cloudformation wait stack-delete-complete --stack-name ${sgStackName} --region ${region}`
          echo "${sgStackName} deleted"
          echo "$deleteStatus"
        fi                 
      fi
  fi
else
  echo "ERROR: elklogging Security Group Does not exist"
fi