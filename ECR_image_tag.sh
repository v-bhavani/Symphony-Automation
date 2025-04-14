#!/bin/bash

# ----------- Config ----------- #
REGION="us-east-1"
REPO_NAME="production/symphony"
AWS_ACCESS_KEY_ID="$Accesskey" 
AWS_SECRET_ACCESS_KEY="$Secretkey"
AWS_DEFAULT_REGION="us-east-1" 

# ----------- Exports ----------- #
export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION


# ----------- Logic ----------- #
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region "$AWS_DEFAULT_REGION")
ECR_URI="$ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com"

# Header
printf "%-20s %-80s\n" "IMAGE TAG" "ECR IMAGE URI"
printf "%-20s %-80s\n" "---------" "--------------"

# Fetch image tags and print formatted
aws ecr describe-images \
  --repository-name "$REPO_NAME" \
  --region "$REGION" \
  --query 'imageDetails[*].imageTags[*]' \
  --output text | tr '\t' '\n' | while read -r TAG; do
    if [ "$TAG" != "None" ]; then
      FULL_URI="$ECR_URI/$REPO_NAME:$TAG"
      printf "%-20s %-80s\n" "$TAG" "$FULL_URI"
    fi
done
