#!/bin/bash

# Input Variables
AWS_REGION="us-east-1"
AWS_ACCOUNT_ID="087273302893"
AWS_ACCESS_KEY_ID="$Accesskey"
AWS_SECRET_ACCESS_KEY="$Secretkey"
ECR_REPO_NAME="anugal/bcs"
S3_BUCKET_NAME="symecrfindings"
S3_KEY_PREFIX="cves"
KMS_KEY_ARN="arn:aws:kms:us-east-1:087273302893:key/f890fb1f-b180-4db0-b0fe-11420270552c"
LOG_FILE="Anugal_ecr_scan.log"
LOCAL_CSV="/home/ec2-user/ECR_ANUGAL_SCAN_REPORT_local$(date +"%d-%m-%Y").csv"
MODIFIED_CSV="/home/ec2-user/ECR_ANUGAL_SCAN_REPORT_$(date +"%d-%m-%Y").csv"

execute_command() {
    local command="$1"
    eval "$command" >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: Command failed - $command. Check logs at $LOG_FILE"
        exit 1
    fi
}

# Check if AWS CLI is installed
if ! [ -x "$(command -v aws)" ]; then
  echo "Error: AWS CLI is not installed."
  exit 1
fi

# Configure AWS CLI
export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export AWS_REGION

# Check if the ECR repository exists
echo "Script started at $(date)"
REPO_CHECK=$(aws ecr describe-repositories --repository-names $ECR_REPO_NAME --region $AWS_REGION 2>/dev/null) >> "$LOG_FILE" 2>&1

if [ -z "$REPO_CHECK" ]; then
  echo "Repository $ECR_REPO_NAME does not exist."
else
  echo "Repository : $ECR_REPO_NAME"
fi

# ECR Login
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com" >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
    echo "ECR Login Failed"
    exit 1
else
    echo "ECR Login Successful"
fi

# Inspector report export to s3
echo "Inspector report exporting to s3."
sleep 100

# Run AWS Inspector2 report generation
report_id=$(aws inspector2 create-findings-report \
    --region "$AWS_REGION" \
    --report-format CSV \
    --s3-destination bucketName="$S3_BUCKET_NAME",keyPrefix="$S3_KEY_PREFIX",kmsKeyArn="$KMS_KEY_ARN" \
    --filter-criteria '{ "ecrImageRepositoryName": [{"comparison": "EQUALS", "value": "'"$ECR_REPO_NAME"'"}] }' | awk 'NR==2{ print; exit }' | awk '{print$2}' | tr -d '"')

echo "Report ID is : ${report_id}"
if [ -z "$report_id" ]; then
    echo "Failed: Report generation encountered an error."
    exit 1
fi

# Download the CSV file from S3
aws s3 cp s3://$S3_BUCKET_NAME/$S3_KEY_PREFIX/$report_id.csv "$LOCAL_CSV"

# Check if the file was downloaded
if [ ! -f "$LOCAL_CSV" ]; then
    echo "Error: CSV file not found!"
    exit 1
fi

# Extract Summary Information
total_vulns=$(tail -n +2 "$LOCAL_CSV" | wc -l) # Count total findings (excluding header)
high_count=$(grep -i "HIGH" "$LOCAL_CSV" | wc -l)
medium_count=$(grep -i "MEDIUM" "$LOCAL_CSV" | wc -l)
low_count=$(grep -i "LOW" "$LOCAL_CSV" | wc -l)
critical_count=$(grep -i "CRITICAL" "$LOCAL_CSV" | wc -l)
untriaged_count=$(grep -i "UNTRIAGED" "$LOCAL_CSV" | wc -l)

# Append Summary to CSV
echo "" >> "$LOCAL_CSV"
echo "Summary Report" >> "$LOCAL_CSV"
echo "Total Findings, $total_vulns" >> "$LOCAL_CSV"
echo "Critical, $critical_count" >> "$LOCAL_CSV"
echo "High, $high_count" >> "$LOCAL_CSV"
echo "Medium, $medium_count" >> "$LOCAL_CSV"
echo "Low, $low_count" >> "$LOCAL_CSV"

# Rename the file with '_SUMMARY'
mv "$LOCAL_CSV" "$MODIFIED_CSV"

# Upload the modified CSV back to S3
aws s3 cp "$MODIFIED_CSV" s3://$S3_BUCKET_NAME/$S3_KEY_PREFIX/

# Cleanup local files
rm -rf "$MODIFIED_CSV"

if [ $? -eq 0 ]; then
    currentdate=$(date +"%d-%m-%Y")  
    echo "##gbStart##currentdate##splitKeyValue##${currentdate}##gbEnd##"
    echo "Report generated, summary added, and exported to S3 successfully."
else
    echo "S3 and local cleanup failed."
    exit 1
fi
