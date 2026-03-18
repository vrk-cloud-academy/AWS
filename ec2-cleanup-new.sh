#!/bin/bash

# Disable AWS CLI pager to avoid interactive output issues
# Ensures script runs smoothly in automation/non-interactive mode
export AWS_PAGER=""

# Fetch and display AWS account ID from current credentials
# Also prints configured default region for verification
echo "Account: $(aws sts get-caller-identity --query Account --output text 2>/dev/null)"
echo "Region : $(aws configure get region)"
echo ""

# Indicate start of EC2 instance discovery process
# Helps user track script progress in terminal output
echo "Fetching running instances..."

# Query AWS to get all running EC2 instance IDs
# Clean output formatting to ensure proper loop execution
INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters Name=instance-state-name,Values=running \
  --query 'Reservations[*].Instances[*].InstanceId' \
  --output text --no-cli-pager 2>/dev/null | tr -d '\r')

# Check if no running instances are found
# Exit termination flow safely if list is empty
if [ -z "$INSTANCE_IDS" ]; then
  echo "No running instances found."
else
  # Display all discovered instance IDs before action
  # Provides visibility and confirmation to user
  echo "Instances found:"
  echo "$INSTANCE_IDS"
  echo ""

  # Loop through each instance and initiate termination
  # Suppress errors to prevent script from stopping midway
  for ID in $INSTANCE_IDS; do
    echo "Terminating $ID ..."
    aws ec2 terminate-instances \
      --instance-ids $ID \
      --no-cli-pager >/dev/null 2>&1
  done

  echo ""
  echo "Waiting for termination..."

  # Wait until each instance reaches terminated state
  # Skip wait errors if instance already terminated or invalid
  for ID in $INSTANCE_IDS; do
    aws ec2 wait instance-terminated \
      --instance-ids $ID \
      --no-cli-pager >/dev/null 2>&1 || echo "Skip wait for $ID"
  done

  echo ""
  echo "✅ All instances termination attempted."
fi

echo ""
echo "Cleaning non-default security groups..."

# Retrieve all security groups except the default one
# Prepare clean list for deletion loop processing
SG_IDS=$(aws ec2 describe-security-groups \
  --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
  --output text --no-cli-pager 2>/dev/null | tr -d '\r')

# Check if any custom security groups exist
# Skip deletion if no eligible groups are found
if [ -z "$SG_IDS" ]; then
  echo "No custom security groups found."
else
  # Loop through each security group for deletion
  # Ignore dependency errors if group is still in use
  for SG in $SG_IDS; do
    echo "Deleting Security Group $SG ..."
    aws ec2 delete-security-group \
      --group-id $SG \
      --no-cli-pager >/dev/null 2>&1 || echo "Skip SG $SG (in use)"
  done
fi

echo ""
echo "✅ Security group cleanup complete (best effort)."
