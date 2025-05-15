#!/bin/bash

projects=("mymigration-322809" "sapspecific")

# Print table header
printf "\n%-30s %-20s %-15s %-20s %-10s %-12s %-25s\n" "VM Name" "Project" "Zone" "VPC" "OS" "State" "Running Time (d:h:m:s)"
printf -- "-------------------------------------------------------------------------------------------------------------------------------\n"

for project in "${projects[@]}"; do
    instances=$(gcloud compute instances list --project="$project" --format="json")
    
    echo "$instances" | jq -c '.[]' | while read -r instance; do
        name=$(echo "$instance" | jq -r '.name')
        zone=$(echo "$instance" | jq -r '.zone' | awk -F/ '{print $NF}')
        vpc=$(echo "$instance" | jq -r '.networkInterfaces[0].network' | awk -F/ '{print $NF}')
        raw_state=$(echo "$instance" | jq -r '.status')

        # Normalize TERMINATED to STOPPED
        [[ "$raw_state" == "TERMINATED" ]] && state="STOPPED" || state="$raw_state"

        # OS detection from disk license
        license=$(echo "$instance" | jq -r '.disks[0].licenses[0] // empty' | awk -F/ '{print $NF}' | tr '[:upper:]' '[:lower:]')
        
        if [[ "$license" == *"windows"* ]]; then
            os="Windows"
        elif [[ "$license" == *"ubuntu"* || "$license" == *"debian"* || "$license" == *"rhel"* || "$license" == *"centos"* || "$license" == *"sles"* ]]; then
            os="Linux"
        else
            # Fallback to label if license is unhelpful
            label_os=$(echo "$instance" | jq -r '.labels.os // empty' | tr '[:upper:]' '[:lower:]')
            if [[ "$label_os" == *"windows"* ]]; then
                os="Windows"
            elif [[ "$label_os" == *"ubuntu"* || "$label_os" == *"debian"* || "$label_os" == *"rhel"* || "$label_os" == *"centos"* || "$label_os" == *"sles"* ]]; then
                os="Linux"
            else
                os="$license"  # fallback: raw license string
            fi
        fi

        # Truncate name if too long
        [[ ${#name} -gt 28 ]] && name="${name:0:28}.."

        # Running time for RUNNING state
        if [[ "$state" == "RUNNING" ]]; then
            start_time=$(echo "$instance" | jq -r '.lastStartTimestamp // empty')
            if [[ -n "$start_time" ]]; then
                start_epoch=$(date -d "$start_time" +%s)
                now_epoch=$(date +%s)
                total_secs=$((now_epoch - start_epoch))
                days=$((total_secs / 86400))
                hours=$(( (total_secs % 86400) / 3600 ))
                mins=$(( (total_secs % 3600) / 60 ))
                secs=$((total_secs % 60))
                uptime="${days}:${hours}:${mins}:${secs}"
            else
                uptime="Unknown"
            fi
        else
            uptime="Instance is $state"
        fi

        printf "%-30s %-20s %-15s %-20s %-10s %-12s %-25s\n" "$name" "$project" "$zone" "$vpc" "$os" "$state" "$uptime"
    done
done

echo -e "\n✅ Report complete.\n"
