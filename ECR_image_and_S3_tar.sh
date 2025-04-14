#!/bin/bash

# ----------- Config ----------- #
REGION="us-east-1"
ECR_REPO="production/symphony"
S3_BUCKET="symphonydistro"
S3_PREFIX="Prod-symphony/"
AWS_ACCESS_KEY_ID="$Accesskey" 
AWS_SECRET_ACCESS_KEY="$Secretkey"
AWS_DEFAULT_REGION="us-east-1" 

# ----------- Exports ----------- #
export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION

# ----------- ECR Setup ----------- #
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region "$AWS_DEFAULT_REGION")
ECR_URI="$ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com"

# ----------- Headers ----------- #
printf "%-20s %-80s %-80s\n" "IMAGE TAG" "ECR IMAGE URI" "LATEST S3 TAR FILE"
printf "%-20s %-80s %-80s\n" "---------" "--------------" "-------------------"

# Get image tags
aws ecr describe-images \
  --repository-name "$ECR_REPO" \
  --region "$AWS_DEFAULT_REGION" \
  --query 'imageDetails[*].imageTags[*]' \
  --output text | tr '\t' '\n' | while read -r TAG; do
    if [ "$TAG" != "None" ]; then
      # Build ECR Image URI
      IMAGE_URI="$ECR_URI/$ECR_REPO:$TAG"

      # Attempt to find matching S3 folder for this image tag
      S3_FOLDER="$S3_PREFIX$TAG/"

      # Get latest file in that folder
      LATEST_FILE=$(aws s3api list-objects-v2 \
        --bucket "$S3_BUCKET" \
        --prefix "$S3_FOLDER" \
        --query 'sort_by(Contents[?ends_with(Key, `.tar`)], &LastModified)[-1].Key' \
        --output text)

      # Build S3 URI if found
      if [ "$LATEST_FILE" != "None" ]; then
        S3_URI="s3://$S3_BUCKET/$LATEST_FILE"
      else
        S3_URI="No .tar file found"
      fi

      # Output final row
      printf "%-20s %-80s %-80s\n" "$TAG" "$IMAGE_URI" "$S3_URI"
    fi
done
