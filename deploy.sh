#!/bin/bash


##
## Preflight checks
##
function haveCmd() { 
    command -v $1  &> /dev/null
    echo $?
}

ret=$(haveCmd aws)
if [[ "$ret" != 0 ]]; then
  echo "Please install aws cli:"
  echo "https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html#getting-started-install-instructions"
  exit 1
fi

ret=$(haveCmd gum)
if [[ "$ret" != 0 ]]; then
  echo "Please install gum: https://github.com/charmbracelet/gum/releases"
  exit 1
fi


if [[ -z "$AWS_ACCESS_KEY_ID" ]]; then
  echo "Environment variable AWS_ACCESS_KEY_ID not set.  Please configure your aws environment:"
  echo "https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-envvars.html"
  exit 1
fi

if [[ -z "$AWS_SECRET_ACCESS_KEY" ]]; then
  echo "Environment variable AWS_SECRET_ACCESS_KEY not set.  Please configure your aws environment:"
  echo "https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-envvars.html"
  exit 1
fi

##
## Set the gum style
##
source style.sh

# CloudFront can only use us-east-1 certificates, so hosting the cloudformation stack
# somewhere else means the certificate and domain aren't associated with the stack.
AWS_DEFAULT_REGION=us-east-1 


function fatal() { 
    local message=$1
    gum style --foreground="$red" "Fatal: $message"
    exit 1
}

##
## Get a domain name
##
rootDomain=$(gum input  --header="Enter the root domain name" --placeholder="example.comn")

if [[ -z "$rootDomain" ]]; then
  gum style "No domain entered, exiting deployment"
  exit 1  
fi


c1="Region: us-east-1"
c2="Domain: docs.$rootDomain"
width=$(( ${#c1} > ${#c2} ? ${#c1} : ${#c2}))
width=$(($width+8))

gum style  --foreground="" --border double \
--align left --width $width --margin "1 1" --padding "1 1" "${c1}" "${c2}"

ready=$(gum confirm --selected.background=$dark)

if [[ $? -ne 0 ]]; then
  gum style "Exiting deployment"
  exit 1  
fi

rootDomainZoneId=$(aws route53 list-hosted-zones-by-name --dns-name $rootDomain --query 'HostedZones[0].Id' | sed -e 's/\/hostedzone\///g' -e 's/"//g')

##
## Start Deployment
## 

stackName=DocumentationStack

aws cloudformation create-stack \
  --stack-name=$stackName \
  --capabilities=CAPABILITY_NAMED_IAM \
  --template-body=file://./infra.yaml \
  --parameters ParameterKey=DomainName,ParameterValue=docs.$rootDomain ParameterKey=RootDomainZoneId,ParameterValue=$rootDomainZoneId \
  --output text 1> /dev/null

if [[ $? -nt 0 ]]; then
  fatal "CloudFormation failed to create stack"
fi

gum spin -s meter --title "Waiting for Stack Creation" --  aws cloudformation wait stack-create-complete --stack-name $stackName
if [[ $? -ne 0 ]]; then
  fatal "CloudFormation failed"
fi


##
## create access keys for the user created in the stack
##
echo
echo "Use these keys as secret variables for your repository: "
aws iam create-access-key --user-name DocsBuilder --query "[['AWS_ACCESS_KEY_ID', AccessKey.AccessKeyId].join('=', @), ['AWS_SECRET_ACCESS_KEY', AccessKey.SecretAccessKey].join('=',@)].join('@',@)" | sed -e "s/\"//g" -e "s/@/\n/"
echo
echo

gum style --foreground="$green" "🟢 Success"
exit 0

