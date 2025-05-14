#!/bin/bash

AWS_ACCESS_KEY_ID=$Accesskey
AWS_SECRET_ACCESS_KEY=$Secretkey
AWS_DEFAULT_REGION=us-east-1

export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION

echo -e "\n📋 Generating AWS EC2 VM Report...\n"

# Print clean header with fixed-width columns
printf "%-40s %-12s %-22s %-10s %-12s %-20s\n" "VM Name" "Region" "VPC ID" "OS" "State" "Running Time (d:h:m:s)"
printf '%0.s-' {1..130}; echo ""

# Get all AWS regions
regions=$(aws ec2 describe-regions --query "Regions[*].RegionName" --output text)

for region in $regions; do
    aws ec2 describe-instances --region "$region" \
        --query "Reservations[*].Instances[*].{Name:Tags[?Key=='Name']|[0].Value, VpcId:VpcId, State:State.Name, LaunchTime:LaunchTime, Platform:Platform}" \
        --output json | jq -c '.[][]' | while read -r instance; do

        name=$(echo "$instance" | jq -r '.Name // "N/A"' | cut -c1-38) # Trim to 38 chars
        vpc_id=$(echo "$instance" | jq -r '.VpcId // "N/A"')
        state=$(echo "$instance" | jq -r '.State')
        launch_time=$(echo "$instance" | jq -r '.LaunchTime')
        os=$(echo "$instance" | jq -r '.Platform // "Linux"')

        # Calculate uptime
        if [[ "$state" == "running" ]]; then
            launch_epoch=$(date -d "$launch_time" +%s)
            now_epoch=$(date +%s)
            seconds=$((now_epoch - launch_epoch))
            days=$((seconds / 86400))
            hours=$(( (seconds % 86400) / 3600 ))
            minutes=$(( (seconds % 3600) / 60 ))
            secs=$((seconds % 60))
            uptime="${days}:${hours}:${minutes}:${secs}"
        else
            uptime="Instance is $state"
        fi

        # Print row aligned with fixed columns
        printf "%-40s %-12s %-22s %-10s %-12s %-20s\n" "$name" "$region" "$vpc_id" "$os" "$state" "$uptime"
    done
done

echo -e "\n✅ Report generation complete.\n"
