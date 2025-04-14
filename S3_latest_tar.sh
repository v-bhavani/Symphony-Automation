#!/bin/bash

# ----------- Config ----------- #
S3_BUCKET="symphonydistro"
S3_PREFIX="Prod-symphony/"
AWS_ACCESS_KEY_ID="$Accesskey" 
AWS_SECRET_ACCESS_KEY="$Secretkey"
AWS_DEFAULT_REGION="us-east-1" 

# ----------- Exports ----------- #
export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION
# Header
printf "%-20s %-80s\n" "IMAGE TAG" "LATEST S3 TAR FILE"
printf "%-20s %-80s\n" "---------" "-------------------"

# List top-level prefixes (folders) under Prod-symphony/
aws s3api list-objects-v2 \
  --bucket "$S3_BUCKET" \
  --prefix "$S3_PREFIX" \
  --delimiter "/" \
  --query 'CommonPrefixes[*].Prefix' \
  --output text | tr '\t' '\n' | while read -r FOLDER; do

    # Extract the tag from the folder name
    TAG=$(basename "$FOLDER")

    # Get latest .tar file from that folder
    LATEST_FILE=$(aws s3api list-objects-v2 \
      --bucket "$S3_BUCKET" \
      --prefix "$FOLDER" \
      --query 'sort_by(Contents[?ends_with(Key, `.tar`)], &LastModified)[-1].Key' \
      --output text)

    if [ "$LATEST_FILE" != "None" ]; then
      S3_URI="s3://$S3_BUCKET/$LATEST_FILE"
    else
      S3_URI="No .tar file found"
    fi

    printf "%-20s %-80s\n" "$TAG" "$S3_URI"
done
