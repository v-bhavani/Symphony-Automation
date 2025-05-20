#!/bin/bash

# Define AWS accounts as an associative array
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

# Declare counters
declare -A running_counts
declare -A stopped_counts

echo -e "\n📋 Generating AWS EC2 VM Report across multiple accounts...\n"
# Print header
printf "%-12s %-40s %-12s %-22s %-10s %-12s %-20s\n" "Account" "VM Name" "Region" "VPC ID" "OS" "State" "Running Time (d:h:m:s)"
printf '%0.s-' {1..140}; echo ""

# Loop through accounts
for account in "${!accounts[@]}"; do
    IFS='|' read -r AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION <<< "${accounts[$account]}"

    export AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY
    export AWS_DEFAULT_REGION

    # Initialize counts
    running_counts["$account"]=0
    stopped_counts["$account"]=0

    # Credential validation
    if ! aws sts get-caller-identity --output text &>/dev/null; then
        echo "⚠️  Skipping '$account': Invalid AWS credentials"
        continue
    fi

    # Get regions (or just use default)
    regions=$(aws ec2 describe-regions --query "Regions[*].RegionName" --output text 2>/dev/null)
    if [[ -z "$regions" ]]; then
        regions="$AWS_DEFAULT_REGION"
    fi

    for region in $regions; do
        # Get instances with proper error handling
        instances_json=$(aws ec2 describe-instances --region "$region" \
            --query "Reservations[*].Instances[*].{Name:Tags[?Key=='Name']|[0].Value, VpcId:VpcId, State:State.Name, LaunchTime:LaunchTime, Platform:Platform}" \
            --output json 2>/dev/null)

        # Skip if no instances or invalid JSON
        if [[ -z "$instances_json" ]] || ! jq -e . >/dev/null 2>&1 <<<"$instances_json"; then
            continue
        fi

        # Process instances
        while IFS= read -r instance; do
            name=$(jq -r '.Name // "N/A"' <<< "$instance" | cut -c1-38)
            vpc_id=$(jq -r '.VpcId // "N/A"' <<< "$instance")
            state=$(jq -r '.State' <<< "$instance")
            launch_time=$(jq -r '.LaunchTime' <<< "$instance")
            os=$(jq -r '.Platform // "Linux"' <<< "$instance")

            if [[ "$state" == "running" ]]; then
                ((running_counts["$account"]++))
                launch_epoch=$(date -d "$launch_time" +%s)
                now_epoch=$(date +%s)
                seconds=$((now_epoch - launch_epoch))
                days=$((seconds / 86400))
                hours=$(( (seconds % 86400) / 3600 ))
                minutes=$(( (seconds % 3600) / 60 ))
                secs=$((seconds % 60))
                uptime="${days}:${hours}:${minutes}:${secs}"
            else
                ((stopped_counts["$account"]++))
                uptime="Instance is $state"
            fi

            printf "%-12s %-40s %-12s %-22s %-10s %-12s %-20s\n" "$account" "$name" "$region" "$vpc_id" "$os" "$state" "$uptime"
        done < <(jq -c '.[][]' <<< "$instances_json")
    done
done

# Summary
echo -e "\n📊 Summary: Running vs Stopped EC2 Instances per Account\n"
printf "%-15s %-20s %-20s\n" "Account" "No. of Running VMs" "No. of Stopped VMs"
printf '%0.s-' {1..60}; echo ""

for account in "${!accounts[@]}"; do
    running=${running_counts["$account"]:-0}
    stopped=${stopped_counts["$account"]:-0}
    printf "%-15s %-20s %-20s\n" "$account" "$running" "$stopped"
done

echo -e "\n✅ Report generation complete across all accounts.\n"
