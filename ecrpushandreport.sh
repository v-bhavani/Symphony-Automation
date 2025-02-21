#!/bin/bash

# Input Variables
AWS_REGION="us-east-1"
AWS_ACCOUNT_ID="087273302893"
AWS_ACCESS_KEY_ID="$Accesskey"
AWS_SECRET_ACCESS_KEY="$Secretkey"
ECR_REPO_NAME="symscan"
eval "IMAGES=($Images)"
S3_BUCKET_NAME="symecrfindings"
S3_KEY_PREFIX="cves/$ECR_REPO_NAME/scanreport$(date +%d%m)"
KMS_KEY_ARN="arn:aws:kms:us-east-1:087273302893:key/f890fb1f-b180-4db0-b0fe-11420270552c"
LOG_FILE="ecr_script.log"

# Function to execute commands and handle errors
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
  aws ecr create-repository --repository-name $ECR_REPO_NAME --region $AWS_REGION --image-scanning-configuration scanOnPush=true >> "$LOG_FILE" 2>&1
  echo "Repository created : $ECR_REPO_NAME"
else
  echo "Repository $ECR_REPO_NAME exists"
fi

# ECR Login
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"  >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
    echo "ECR Login Failed"
    exit 1
else
    echo "ECR Login Successful"
fi

# Array to store all image tags
IMAGE_TAGS=()

# Push images to ECR and collect tags
for IMAGE in "${IMAGES[@]}"; do
  if [[ -z "$IMAGE" ]]; then
     echo "Error: Image name is empty or not provided."
    exit 1
  fi

  IMAGE_TAGGED="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO_NAME:${IMAGE##*:}"
  
  # Check if the image exists locally before tagging
  if ! docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^$IMAGE$"; then
    echo "Error: Image $IMAGE does not exist locally."
    exit 1
  fi

  docker tag $IMAGE $IMAGE_TAGGED  >> "$LOG_FILE" 2>&1
  if [ $? -ne 0 ]; then
    echo "Error: Failed to tag image $IMAGE."
    exit 1
  fi
  echo "Image tagged: $IMAGE_TAGGED"

  docker push $IMAGE_TAGGED  >> "$LOG_FILE" 2>&1
  if [ $? -ne 0 ]; then
    echo "Error: Failed to push image $IMAGE_TAGGED."
    exit 1
  fi
  echo "Image pushed to $ECR_REPO_NAME."

  IMAGE_TAGS+=("${IMAGE##*:}")

  # Clean up locally tagged images
  docker rmi "$IMAGE_TAGGED"  >> "$LOG_FILE" 2>&1
  if [ $? -ne 0 ]; then
      echo "Warning: Failed to remove local image $IMAGE_TAGGED"
  else
      echo "Successfully removed local image: $IMAGE_TAGGED"
  fi
done

# Wait for Inspector scanning to complete
echo "Waiting for Inspector report generation..."
sleep 100

echo "Inspector report export to S3."

# Convert IMAGE_TAGS array into JSON format required for AWS Inspector2
IMAGE_TAGS_JSON=$(printf '{"comparison": "EQUALS", "value": "%s"},' "${IMAGE_TAGS[@]}")
IMAGE_TAGS_JSON="[${IMAGE_TAGS_JSON%,}]"  # Remove the last comma and wrap in brackets

# Create a single report for all images
report_id=$(aws inspector2 create-findings-report \
  --region "$AWS_REGION" \
  --report-format CSV \
  --s3-destination bucketName="$S3_BUCKET_NAME",keyPrefix="$S3_KEY_PREFIX",kmsKeyArn="$KMS_KEY_ARN" \
  --filter-criteria "{\"ecrImageRepositoryName\": [{\"comparison\": \"EQUALS\", \"value\": \"$ECR_REPO_NAME\"}], \"ecrImageTags\": $IMAGE_TAGS_JSON }" | awk 'NR==2{ print; exit }' | awk '{print$2}' | tr -d '"')
sleep 5
echo "Report ID is : ${report_id}"
echo "##gbStart##reportid##splitKeyValue##${report_id}##gbEnd##"

if [ $? -eq 0 ]; then
    echo "Report generated and exported to S3 successfully."
else
    echo "Failed: Report generation encountered an error."
    exit 1
fi
