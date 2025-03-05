#!/bin/bash

# Input Variables
AWS_REGION="us-east-1"
AWS_ACCOUNT_ID="087273302893"
AWS_ACCESS_KEY_ID="$Accesskey"
AWS_SECRET_ACCESS_KEY="$Secretkey"
TAGNAME="$Tagname"
ECR_REPO_NAME="production/symphony"
S3_BUCKET_NAME="symecrfindings"
S3_KEY_PREFIX="cves"
KMS_KEY_ARN="arn:aws:kms:us-east-1:087273302893:key/f890fb1f-b180-4db0-b0fe-11420270552c"
LOG_FILE="symphony_ecr_scan.log"
Local_csv_path="/home/ec2-user/SYMPHONY_SCAN_REPORT_local$(date +"%d-%m-%Y").csv"
Final_csv_path="/home/ec2-user/SYMPHONY_SCAN_REPORT_$(date +"%d-%m-%Y").csv"
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
symphony_report_id=$(aws inspector2 create-findings-report \
    --region "$AWS_REGION" \
    --report-format CSV \
    --s3-destination bucketName="$S3_BUCKET_NAME",keyPrefix="$S3_KEY_PREFIX",kmsKeyArn="$KMS_KEY_ARN" \
    --filter-criteria '{ "ecrImageRepositoryName": [{"comparison": "EQUALS", "value": "'"$ECR_REPO_NAME"'"}],
                         "ecrImageTags": [{"comparison": "EQUALS", "value": "$TAGNAME"}] }' | awk 'NR==2{ print; exit }' | awk '{print$2}' | tr -d '"')
echo "Report ID is : ${symphony_report_id}"
if [ -z "$symphony_report_id" ]; then
    echo "Failed: Report generation encountered an error."
    exit 1
fi
# Download the CSV file from S3
sleep 20
aws s3 cp s3://$S3_BUCKET_NAME/$S3_KEY_PREFIX/$symphony_report_id.csv $Local_csv_path >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
    echo "Failed to download file from S3."
    exit 1
fi
# Extract Summary Information from the 2nd column (Severity column)
total_vulns=$(tail -n +2 "$Local_csv_path" | cut -d',' -f2 | wc -l)  # Count total findings (excluding header)
high_count=$(tail -n +2 "$Local_csv_path" | cut -d',' -f2 | grep -i "HIGH" | wc -l)
medium_count=$(tail -n +2 "$Local_csv_path" | cut -d',' -f2 | grep -i "MEDIUM" | wc -l)
low_count=$(tail -n +2 "$Local_csv_path" | cut -d',' -f2 | grep -i "LOW" | wc -l)
critical_count=$(tail -n +2 "$Local_csv_path" | cut -d',' -f2 | grep -i "CRITICAL" | wc -l)
untriaged_count=$(tail -n +2 "$Local_csv_path" | cut -d',' -f2 | grep -i "UNTRIAGED" | wc -l)
# Append Summary to CSV
echo "" >> "$Local_csv_path"
echo "Summary Report" >> "$Local_csv_path"
echo "Total Findings, $total_vulns" >> "$Local_csv_path"
echo "Critical, $critical_count" >> "$Local_csv_path"
echo "High, $high_count" >> "$Local_csv_path"
echo "Medium, $medium_count" >> "$Local_csv_path"
echo "Low, $low_count" >> "$Local_csv_path"
echo "Untriaged, $untriaged_count" >> "$Local_csv_path"
# Rename the CSV file
mv $Local_csv_path $Final_csv_path
if [ $? -ne 0 ]; then
    echo "Failed to rename file."
    exit 1
fi
# Upload the modified CSV back to S3
aws s3 cp $Final_csv_path s3://$S3_BUCKET_NAME/$S3_KEY_PREFIX/ >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
    echo "Failed to upload file to S3."
    exit 1
fi
# Remove the original CSV from S3
aws s3 rm s3://$S3_BUCKET_NAME/$S3_KEY_PREFIX/$symphony_report_id.csv >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
    echo "Failed to delete original file from S3."
    exit 1
fi
# Cleanup local files
sudo rm -rf $Final_csv_path >> "$LOG_FILE" 2>&1
if [ $? -eq 0 ]; then
    currentdate=$(date +"%d-%m-%Y")  
    echo "##gbStart##currentdate##splitKeyValue##${currentdate}##gbEnd##"
    echo "Report generated, summary added, and exported to S3 successfully."
else
    echo "Local cleanup failed."
    exit 1
fi
