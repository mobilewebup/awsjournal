#!/bin/bash
# Guess the minimal instance type that can be used for an image.
# usage:
#   minimal-itype.sh [-r region] -a ami_id
# Note that EC2_PRIVATE_KEY and EC2_CERT must be set in your environment.

region=$EC2_REGION
while getopts 'a:r:' arg; do
    case $arg in 
	'a') ami="$OPTARG";
	    ;;
	'r') region="$OPTARG";
	    ;;
    esac
done

if [ -z "$ami" ]; then
    echo "usage: minimal-itype.sh [-r region] -a ami_id"
    exit 1
fi

# sniff arch from the base ami
arch=$(ec2-describe-images --region $region $ami | grep '^IMAGE' | cut -f 8)

if [ "x86_64" == "$arch" ]; then
    # 64 bit
    itype='t1.micro'
else
    # 32 bit
    itype='x1.small'
fi
echo $itype
