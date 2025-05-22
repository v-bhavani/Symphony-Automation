#!/bin/bash

# Input Variables
AWS_REGION="us-east-1"
AWS_ACCOUNT_ID="087273302893"
AWS_ACCESS_KEY_ID="$Accesskey"
AWS_SECRET_ACCESS_KEY="$Secretkey"
TAGNAME="$Tagname"
ECR_REPO_NAME="$Repo"
S3_BUCKET_NAME="symecrfindings"
S3_KEY_PREFIX="cves"
KMS_KEY_ARN="arn:aws:kms:us-east-1:087273302893:key/f890fb1f-b180-4db0-b0fe-11420270552c"
LOG_FILE="symphony_ecr_scan.log"
# Generate timestamp
TIMESTAMP=$(date +"%d-%m-%Y_%H-%M-%S")

# Define file names with TAGNAME and timestamp
Local_csv_path="/home/ec2-user/${Repo}_SCAN_REPORT_${TAGNAME}_${TIMESTAMP}_local.csv"
Final_csv_path="/home/ec2-user/${Repo}_SCAN_REPORT_${TAGNAME}_${TIMESTAMP}.xlsx"
Final_csv_name="${Repo}_SCAN_REPORT_${TAGNAME}_${TIMESTAMP}.xlsx"

execute_command() {
    local command="$1"
    eval "$command" >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: Command failed - $command. Check logs at $LOG_FILE"
        exit 1
    fi
}

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI is not installed."
    exit 1
fi

# Configure AWS CLI
export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export AWS_REGION

# Check if the ECR repository exists
echo "Script started at $(date)"
REPO_CHECK=$(aws ecr describe-repositories --repository-names "$ECR_REPO_NAME" --region "$AWS_REGION" 2>/dev/null)
if [ -z "$REPO_CHECK" ]; then
    echo "Repository $ECR_REPO_NAME does not exist."
else
    echo "Repository: $ECR_REPO_NAME"
fi

# ECR Login
execute_command "aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
echo "ECR Login Successful"

# Inspector report export to S3
echo "Inspector report exporting to S3."
sleep 100

# Run AWS Inspector2 report generation
symphony_report_id=$(aws inspector2 create-findings-report \
    --region "$AWS_REGION" \
    --report-format CSV \
    --s3-destination bucketName="$S3_BUCKET_NAME",keyPrefix="$S3_KEY_PREFIX",kmsKeyArn="$KMS_KEY_ARN" \
    --filter-criteria '{ "ecrImageRepositoryName": [{"comparison": "EQUALS", "value": "'"$ECR_REPO_NAME"'"}],
                         "ecrImageTags": [{"comparison": "EQUALS", "value": "'"$TAGNAME"'"}] }' | jq -r '.reportId')

if [ -z "$symphony_report_id" ]; then
    echo "Failed: Report generation encountered an error."
    exit 1
fi
echo "Report ID is: ${symphony_report_id}"

# Download the CSV file from S3
sleep 20
execute_command "aws s3 cp s3://$S3_BUCKET_NAME/$S3_KEY_PREFIX/$symphony_report_id.csv $Local_csv_path"

# Extract Summary Information
total_vulns=$(tail -n +2 "$Local_csv_path" | cut -d',' -f2 | wc -l)
high_count=$(grep -i "HIGH" "$Local_csv_path" | wc -l)
medium_count=$(grep -i "MEDIUM" "$Local_csv_path" | wc -l)
low_count=$(grep -i "LOW" "$Local_csv_path" | wc -l)
critical_count=$(grep -i "CRITICAL" "$Local_csv_path" | wc -l)
untriaged_count=$(grep -i "UNTRIAGED" "$Local_csv_path" | wc -l)

# Append Summary to CSV
echo "" >> "$Local_csv_path"
echo "Summary Report" >> "$Local_csv_path"
echo "Total Findings, $total_vulns" >> "$Local_csv_path"
echo "Critical, $critical_count" >> "$Local_csv_path"
echo "High, $high_count" >> "$Local_csv_path"
echo "Medium, $medium_count" >> "$Local_csv_path"
echo "Low, $low_count" >> "$Local_csv_path"
echo "Untriaged, $untriaged_count" >> "$Local_csv_path"

# Convert CSV to XLSX
python3 -c "import pandas as pd; pd.read_csv('$Local_csv_path').to_excel('$Final_csv_path', index=False)"
if [ $? -ne 0 ]; then
    echo "Failed to convert CSV to XLSX."
    exit 1
fi

# Upload the modified CSV back to S3
execute_command "aws s3 cp $Final_csv_path s3://$S3_BUCKET_NAME/$S3_KEY_PREFIX/"

# Remove the original CSV from S3
execute_command "aws s3 rm s3://$S3_BUCKET_NAME/$S3_KEY_PREFIX/$symphony_report_id.csv"

# Cleanup local files
rm -rf "$Final_csv_path"
if [ $? -eq 0 ]; then
    currentdate=$(date +"%d-%m-%Y_%H-%M-%S")  
    echo "##gbStart##currentdate##splitKeyValue##${currentdate}##gbEnd##"
    echo "##gbStart##Final_csv_name##splitKeyValue##${Final_csv_name}##gbEnd##"
    echo "Report generated, summary added, and exported to S3 successfully."
else
    echo "Local cleanup failed."
    exit 1
fi
