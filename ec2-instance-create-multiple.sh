#!/bin/bash
set -e

export AWS_PAGER=""

# -------- CONFIG --------
INSTANCE_TYPE="t3.micro"
TTL_MINUTES=30   # auto delete after X mins
TODAY=$(date +%d%m)
INSTANCE_NAME="Instance_${TODAY}"
LOG_FILE="cleanup.log"

echo "===== Run at $(date) =====" >> $LOG_FILE

# ------------------------------------
# Input: Number of Instances
# ------------------------------------
read -p "Enter number of EC2 instances to create [Default: 1]: " INSTANCE_COUNT
INSTANCE_COUNT=${INSTANCE_COUNT:-1}

if ! [[ "$INSTANCE_COUNT" =~ ^[0-9]+$ ]]; then
  echo "❌ Invalid input. Using default = 1"
  INSTANCE_COUNT=1
fi

echo "🚀 Instances to be created: $INSTANCE_COUNT"

echo "------------------------------------"
echo "Stage 1: Fetch Latest Amazon Linux AMI"
echo "------------------------------------"

AMI_ID=$(aws ssm get-parameters \
--names /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 \
--query 'Parameters[0].Value' \
--output text | tr -d '\r\n')

echo "Using AMI: $AMI_ID" | tee -a $LOG_FILE

echo "------------------------------------"
echo "Stage 2: Select Key Pair"
echo "------------------------------------"

KEY_LIST=$(aws ec2 describe-key-pairs \
--query 'KeyPairs[*].KeyName' \
--output text)

echo "Available Key Pairs:"
select KEY_NAME in $KEY_LIST "Create-New"; do
    if [ "$KEY_NAME" == "Create-New" ]; then
        read -p "Enter new key name: " KEY_NAME
        aws ec2 create-key-pair \
        --key-name $KEY_NAME \
        --query 'KeyMaterial' \
        --output text > ${KEY_NAME}.pem
        chmod 400 ${KEY_NAME}.pem
        break
    elif [ -n "$KEY_NAME" ]; then
        echo "Selected key: $KEY_NAME"
        break
    else
        echo "Invalid selection"
    fi
done

echo "------------------------------------"
echo "Stage 3: Setup Network"
echo "------------------------------------"

VPC_ID=$(aws ec2 describe-vpcs \
--filters Name=isDefault,Values=true \
--query 'Vpcs[0].VpcId' \
--output text | tr -d '\r\n')

SUBNET_ID=$(aws ec2 describe-subnets \
--filters Name=vpc-id,Values=$VPC_ID \
--query 'Subnets[0].SubnetId' \
--output text | tr -d '\r\n')

echo "VPC: $VPC_ID | Subnet: $SUBNET_ID" | tee -a $LOG_FILE

SG_ID=$(aws ec2 create-security-group \
--group-name "ssh-${TODAY}-$$" \
--description "SSH Access" \
--vpc-id $VPC_ID \
--query 'GroupId' \
--output text | tr -d '\r\n')

echo "SG: $SG_ID" | tee -a $LOG_FILE

aws ec2 authorize-security-group-ingress \
--group-id "$SG_ID" \
--protocol tcp \
--port 22 \
--cidr 0.0.0.0/0

echo "------------------------------------"
echo "Stage 4: Launch Instances"
echo "------------------------------------"

INSTANCE_IDS=()

for ((i=1; i<=INSTANCE_COUNT; i++)); do
  echo "🔹 Creating instance $i..."

  ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type $INSTANCE_TYPE \
  --key-name "$KEY_NAME" \
  --network-interfaces "DeviceIndex=0,SubnetId=$SUBNET_ID,Groups=$SG_ID,AssociatePublicIpAddress=true" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${INSTANCE_NAME}_$i}]" \
  --query 'Instances[0].InstanceId' \
  --output text | tr -d '\r\n')

  echo "✅ Instance ID: $ID" | tee -a $LOG_FILE
  INSTANCE_IDS+=("$ID")
done

echo "------------------------------------"
echo "Stage 5: Wait for Instances"
echo "------------------------------------"

aws ec2 wait instance-running --instance-ids "${INSTANCE_IDS[@]}"

PUBLIC_IPS=()

for ID in "${INSTANCE_IDS[@]}"; do
  IP=$(aws ec2 describe-instances \
  --instance-ids "$ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text | tr -d '\r\n')

  echo "🌐 $ID → $IP" | tee -a $LOG_FILE
  PUBLIC_IPS+=("$IP")
done

FIRST_IP=${PUBLIC_IPS[0]}

# -------- AUTO DELETE BACKGROUND --------
(
    sleep $((TTL_MINUTES*60))
    echo "Auto cleanup started..." >> $LOG_FILE

    aws ec2 terminate-instances --instance-ids "${INSTANCE_IDS[@]}" >> $LOG_FILE 2>&1
    aws ec2 wait instance-terminated --instance-ids "${INSTANCE_IDS[@]}" >> $LOG_FILE 2>&1

    aws ec2 delete-security-group --group-id "$SG_ID" >> $LOG_FILE 2>&1

    echo "Cleanup done for all instances" >> $LOG_FILE
) &

echo "------------------------------------"
echo "Stage 6: SSH Connect (First Instance)"
echo "------------------------------------"

sleep 15

if [ ! -f "${KEY_NAME}.pem" ]; then
    echo "❌ PEM file missing: ${KEY_NAME}.pem"
    exit 1
fi

mkdir -p ~/.ssh
ssh-keyscan -H "$FIRST_IP" >> ~/.ssh/known_hosts 2>/dev/null

echo "Connecting to $FIRST_IP ..."
ssh -o StrictHostKeyChecking=no -i "${KEY_NAME}.pem" ec2-user@"$FIRST_IP"
