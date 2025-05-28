#!/bin/bash
AZURE_CLIENT_ID="$clientid"
AZURE_CLIENT_SECRET="$clientsecret"
AZURE_TENANT_ID="$tenantid"
SUBSCRIPTION_ID="$subscriptionid"
# Login to Azure using Service Principal
az login --service-principal --username "$AZURE_CLIENT_ID" --password="$AZURE_CLIENT_SECRET" --tenant "$AZURE_TENANT_ID" >/dev/null 2>&1
az account set --subscription "$SUBSCRIPTION_ID" >/dev/null 2>&1

if [[ $? -ne 0 ]]; then
    echo "❌ Azure login failed. Please check your Service Principal credentials."
    exit 1
fi

# echo -e "\n🔐 Logged in with Service Principal"
echo -e "\nGenerating Azure VM Uptime Report...\n"

# Print table header with Users column
printf "%-25s %-25s %-15s %-10s %-15s %-30s %-15s\n" "VM Name" "Resource Group" "Power State" "OS Type" "Location" "Uptime/Downtime" "Users"
echo "------------------------------------------------------------------------------------------------------------------------------------------"

# Function to convert Linux uptime to days:hours:minutes:seconds format
convert_linux_uptime() {
    local uptime_str=$1
    local days=0 hours=0 minutes=0 seconds=0
    
    # Handle different uptime formats (days, hours:minutes, or minutes)
    if [[ $uptime_str =~ up[[:space:]]+([0-9]+)[[:space:]]+day ]]; then
        days=${BASH_REMATCH[1]}
        uptime_str=${uptime_str#* day}
        uptime_str=${uptime_str#* days}
    fi
    
    if [[ $uptime_str =~ up[[:space:]]+([0-9]+):([0-9]+) ]]; then
        hours=${BASH_REMATCH[1]}
        minutes=${BASH_REMATCH[2]}
    elif [[ $uptime_str =~ up[[:space:]]+([0-9]+)[[:space:]]+min ]]; then
        minutes=${BASH_REMATCH[1]}
    fi
    
    # Remove leading zeros to avoid octal interpretation
    days=$((10#$days))
    hours=$((10#$hours))
    minutes=$((10#$minutes))
    seconds=$((10#$seconds))
    
    printf "%d:%02d:%02d:%02d" "$days" "$hours" "$minutes" "$seconds"
}

# Function to get Windows uptime with better error handling
get_windows_uptime() {
    local rg_name=$1
    local vm_name=$2
    
    # Try multiple methods to get uptime
    uptime_output=$(az vm run-command invoke \
        --resource-group "$rg_name" \
        --name "$vm_name" \
        --command-id RunPowerShellScript \
        --scripts "\$os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue;
                   if (\$os) { 
                       \$uptime = (Get-Date) - \$os.LastBootUpTime;
                       '{0}:{1:00}:{2:00}:{3:00}' -f \$uptime.Days, \$uptime.Hours, \$uptime.Minutes, \$uptime.Seconds
                   } else {
                       'Error: Could not get OS info'
                   }" \
        --query "value[0].message" -o tsv 2>/dev/null | tr -d '\r')
    
    # If first method fails, try alternative method
    if [[ "$uptime_output" == *"Error"* ]] || [[ -z "$uptime_output" ]]; then
        uptime_output=$(az vm run-command invoke \
            --resource-group "$rg_name" \
            --name "$vm_name" \
            --command-id RunPowerShellScript \
            --scripts "(Get-Date) - [System.Management.ManagementDateTimeconverter]::ToDateTime((Get-WmiObject Win32_OperatingSystem).LastBootUpTime) | 
                        ForEach-Object { '{0}:{1:00}:{2:00}:{3:00}' -f \$_.Days, \$_.Hours, \$_.Minutes, \$_.Seconds }" \
            --query "value[0].message" -o tsv 2>/dev/null | tr -d '\r')
    fi
    
    echo "$uptime_output"
}

# Get all VMs
az vm list --show-details --query "[].{name:name, rg:resourceGroup, power:powerState, os:storageProfile.osDisk.osType, location:location}" -o tsv |
while IFS=$'\t' read -r vm_name rg_name power_state os_type location; do

    uptime_info=""
    user_info=""

    if [[ "$power_state" == "VM running" ]]; then
        if [[ "$os_type" == "Linux" ]]; then
            # Get uptime from Linux VM
            raw_output=$(az vm run-command invoke \
                --resource-group "$rg_name" \
                --name "$vm_name" \
                --command-id RunShellScript \
                --scripts "uptime" \
                --query "value[0].message" -o tsv 2>/dev/null)

            # Extract uptime and users separately
            uptime_raw=$(echo "$raw_output" | grep -oP 'up\s+[^,]+' | head -n1)
            user_count=$(echo "$raw_output" | grep -oP ',\s+\d+\s+user' | grep -oP '\d+' || echo "0")
            
            if [[ -n "$uptime_raw" ]]; then
                uptime_info=$(convert_linux_uptime "$uptime_raw")
                uptime_info="Up $uptime_info (days:hh:mm:ss)"
                user_info="$user_count user$( [ "$user_count" -ne 1 ] && echo "s" )"
            else
                uptime_info="Uptime unavailable"
                user_info="N/A"
            fi

        elif [[ "$os_type" == "Windows" ]]; then
            # Get Windows uptime with improved reliability
            uptime_output=$(get_windows_uptime "$rg_name" "$vm_name")
            
            # Get logged in users
            user_output=$(az vm run-command invoke \
                --resource-group "$rg_name" \
                --name "$vm_name" \
                --command-id RunPowerShellScript \
                --scripts "(quser 2>&1 | Out-String).Trim()" \
                --query "value[0].message" -o tsv 2>/dev/null | tr -d '\r')
            
            # Count users (handles cases where quser fails)
            if [[ "$user_output" =~ "No User exists" ]] || [[ "$user_output" == *"error"* ]]; then
                user_count=0
            else
                user_count=$(echo "$user_output user(s)" | grep -c '^\w' || echo "0")
            fi
            
            if [[ "$uptime_output" == *"Error"* ]] || [[ -z "$uptime_output" ]]; then
                uptime_info="Uptime query failed"
                user_info="N/A"
            else
                uptime_info="Up $uptime_output (days:hh:mm:ss)"
                user_info="$user_count user(s)$( [ "$user_count" -ne 1 ] && echo "s" )"
            fi
        else
            uptime_info="Unknown OS"
            user_info="N/A"
        fi
    else
        uptime_info="VM is currently stopped"
        user_info="N/A"
    fi

    # Print formatted row
    printf "%-25s %-25s %-15s %-10s %-15s %-30s %-15s\n" "$vm_name" "$rg_name" "$power_state" "$os_type" "$location" "$uptime_info" "$user_info"
done

az logout
echo -e "\n✅ Report complete.\n"

