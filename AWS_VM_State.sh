#!/bin/bash

# Define AWS accounts as an array of account config blocks
declare -A accounts

# Format: accounts[<alias>]="$AWS_ACCESS_KEY_ID|$AWS_SECRET_ACCESS_KEY|$AWS_DEFAULT_REGION"
accounts["Main"]="$accesskey08|$secretkey08|us-east-1"
accounts["Demo"]="$accesskey07|$secretkey07|us-east-1"
accounts["Rhel"]="$accesskey03|$secretkey03|us-east-1"
accounts["Abap"]="$accesskey01|$secretkey01|us-east-1"
accounts["Xgen"]="$accesskey21|$secretkey21|us-east-1"
accounts["bcs"]="$accesskey63|$secretkey63|us-east-1"
accounts["Nadhas"]="$accesskey76|$secretkey76|us-east-1"
accounts["Account91"]="$accesskey91|$secretkey91|us-east-1"
accounts["Growfin"]="$accesskey92|$secretkey92|us-east-1"

echo -e "\n📋 Generating AWS EC2 VM Report across multiple accounts...\n"

# Print header once
printf "%-12s %-40s %-12s %-22s %-10s %-12s %-20s\n" "Account" "VM Name" "Region" "VPC ID" "OS" "State" "Running Time (d:h:m:s)"
printf '%0.s-' {1..140}; echo ""

# Loop through each account
for account in "${!accounts[@]}"; do
    IFS='|' read -r AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION <<< "${accounts[$account]}"
    
    export AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY
    export AWS_DEFAULT_REGION

    # Get all regions (skip if you'd rather use just AWS_DEFAULT_REGION)
    regions=$(aws ec2 describe-regions --query "Regions[*].RegionName" --output text 2>/dev/null)

    for region in $regions; do
        aws ec2 describe-instances --region "$region" \
            --query "Reservations[*].Instances[*].{Name:Tags[?Key=='Name']|[0].Value, VpcId:VpcId, State:State.Name, LaunchTime:LaunchTime, Platform:Platform}" \
            --output json 2>/dev/null | jq -c '.[][]' | while read -r instance; do

            name=$(echo "$instance" | jq -r '.Name // "N/A"' | cut -c1-38)
            vpc_id=$(echo "$instance" | jq -r '.VpcId // "N/A"')
            state=$(echo "$instance" | jq -r '.State')
            launch_time=$(echo "$instance" | jq -r '.LaunchTime')
            os=$(echo "$instance" | jq -r '.Platform // "Linux"')

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

            printf "%-12s %-40s %-12s %-22s %-10s %-12s %-20s\n" "$account" "$name" "$region" "$vpc_id" "$os" "$state" "$uptime"
        done
    done
done

echo -e "\n✅ Report generation complete across all accounts.\n"
