#!/bin/bash
# Run an EC2 instance, and associate it with an elastic IP address.
#
# usage:
#   run-and-associate.sh -a ami_id -I elastic_ip_address -r region [ -t instance_type ]
# Note that EC2_PRIVATE_KEY and EC2_CERT must be set in your environment.
#
# Be careful that the elastic IP has already been allocated, and that
# it isn't already associated.  If that happens, the program will
# still create the instance, not associate it with any elastic IP, and
# terminate with an error.
#
# This script's code is in the public domain.
# Development sponsored by Mobile Web Up ( http://mobilewebup.com )

function exit_usage {
    ec=${1:-0}
    echo "INFO	Usage: run-and-associate.sh -a ami_id -I elastic_ip_address [ -t instance_type ] [ -r region ]"
    exit $ec
}

region=$EC2_REGION
while getopts 'I:a:t:r:' arg; do
    case $arg in 
	'a') ami="$OPTARG"
	    ;;
	'r') region="$OPTARG"
	    ;;
	'I') eip="$OPTARG"
	    ;;
        't') itype="$OPTARG"
            ;;
    esac
done

for required in ami region eip; do
    if [ -z "${!required}" ]; then
	echo "ERROR	$required option is required."
	exit_usage 1
    fi
done

if [ -z "$itype" ]; then
    # Can we use minimal-itype.sh ?
    which minimal-itype.sh > /dev/null 2>&1
    if [ 0 == $? ]; then
	itype=$(minimal-itype.sh -r $region -a $ami)
    fi
    if [ -z "$itype" ]; then
	# Something went wrong!
	echo "ERROR	Cannot automatically determine instance type.  Re-run with -t option"
	exit_usage 1
    fi
fi

instanceid=$(ec2-run-instances --region "$region" -t "$itype" "$ami" | grep '^INSTANCE' | cut -f 2)

# Wait on the instance to get up and running
function get_instance_status {
    ec2-describe-instances --region $region $instanceid | grep '^INSTANCE' | cut -f 6
}
check_status=$(get_instance_status)
if [ -z "$check_status" ]; then
    # Maybe it's just not visible yet.  Wait and try again
    sleep 60s
    check_status=$(get_instance_status)
    if [ -z "$check_status" ]; then
	echo "ERROR	Instance $instanceid not found!"
	exit 2
    fi
fi
while [ "$check_status" != "running" ]; do
    echo "INFO	waiting for $instanceid to reach status 'running'... (latest: '$check_status')"
    sleep 60s
    check_status=$(get_instance_status)
done


if [ 0 == $? ]; then
    ec2-associate-address -i "$instanceid" "$eip"
else
    echo "ERROR	Unable to verify running of instance.  *NOT* associating IP address."
    exit 3
fi
