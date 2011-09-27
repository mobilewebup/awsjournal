#!/bin/bash
# usage:
#  clone-ami.sh -a base_ami -n ami_name -r region [-t seed_instance_type]
# Note that EC2_PRIVATE_KEY and EC2_CERT must be set in your environment.
#
# This script will create an AMI that is essentially a clone of
# another.  This is useful, for example, to preserve a public AMI that
# we'll be able to use even if the original is no longer publicly
# available.
#
# This script operates by creating an intermediate instance of the
# seed AMI, then attempts to terminate the instance when the clone
# is created.  If anything goes wrong, you might have to terminate
# that image yourself.  An INFO line with the command to terminate
# that instance is emitted first thing, in case you need it.
#
# If all goes well, the script will emit a line to stdout with the
# word IMAGE, then a tab, then the ami ID of the new created image.
#
# This script partly depends on minimal-itype.sh, included in this
# project.  If that's not available, specify an instance type to use
# with the -t option.
#
# This script's code is in the public domain.
# Development sponsored by Mobile Web Up ( http://mobilewebup.com )

function exit_usage() {
    echo "usage: $(basename $0) -a ami -n aminame [-r region] [-t instance_type]"
    exit 0
}

region=$EC2_REGION

while getopts 'r:a:n:t:' arg; do
    case $arg in
        'r') region="$OPTARG"
            ;;
        'a') ami="$OPTARG"
            ;;
        'n') name="$OPTARG"
            ;;
        't') itype="$OPTARG"
            ;;
    esac
done
#set -x

if [ -z "$region" ]; then
    echo 'Region (-r option) is required'
    exit_usage
fi

if [ -z "$ami" ]; then
    echo 'Base AMI id (-a option) is required'
    exit_usage
fi

if [ -z "$name" ]; then
    echo 'New AMI name (-n option) is required'
    exit_usage
fi

if [ -z "$itype" ]; then
    itype=$(minimal-itype.sh -r $region -a $ami)
fi

instanceid=$(ec2-run-instances --region "$region" -t "$itype" "$ami" | grep '^INSTANCE' | cut -f 2)
if [ -z "$instanceid" ]; then
    echo "FATAL	Could not create instance"
    exit 2
fi

echo "INFO	Instance terminate command: ec2-terminate-instances --region $region $instanceid"
function terminate_seed_instance {
    ec2-terminate-instances --region "$region" "$instanceid"
}
echo "INFO	Created instance $instanceid from AMI $ami"
echo "INFO	Waiting on instance $instanceid to reach \"running\" state..."
# Wait on the seed instance to get up and running
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
	# Just in case, issue the terminate command.  Probably will be a no-op in this situation, though.
	terminate_seed_instance
	exit 2
    fi
fi
while [ "$check_status" != "running" ]; do
    echo "INFO	waiting for $instanceid to reach status 'running'... (latest: '$check_status')"
    sleep 60s
    check_status=$(get_instance_status)
done

echo "INFO	Creating new AMI from instance $instanceid"
ami=$(ec2-create-image --region "$region" -n "$name" "$instanceid" | grep '^IMAGE' | cut -f 2)
echo "INFO	Waiting on creation of ami \"$ami\" to complete"

# Wait on the AMI creation to complete.  Note that this needs to
# finish before we can terminate the seed instance, otherwise the AMI
# will break.
#waitonami.sh -r "$region" $ami 'available'
function get_ami_status {
    ec2-describe-images --region $region $ami | grep '^IMAGE' | cut -f 5
}
check_status=$(get_ami_status)
if [ -z "$check_status" ]; then
    # Just like with the seed instance, maybe this image just isn't visible yet.  Wait and try again
    sleep 60s
    check_status=$(get_ami_status)
    if [ -z "$check_status" ]; then
	echo "ERROR	Image $ami not found!"
	terminate_seed_instance
	exit 2
    fi
fi
while [ "$check_status" != "available" ]; do
    echo "INFO	waiting for AMI $amiid to reach status 'available'... (latest: '$check_status')"
    sleep 60s
    check_status=$(get_ami_status)
done

echo "INFO	Terminating seed instance $instanceid"
terminate_seed_instance
echo "INFO	Created new AMI image: $ami"
echo "IMAGE	$ami"