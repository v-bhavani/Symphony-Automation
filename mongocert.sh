#!/bin/bash

# Variables
AWS_ACCOUNT_ID="087273302893"
BITBUCKET_USERNAME="subash_bcs" # Replace with your Bitbucket username
PAT="$Bitbucketpat"   # Replace with your PAT
REPO_URL="https://${BITBUCKET_USERNAME}:${PAT}@bitbucket.org/bcs_team_dev/sym_distro_mongo.git" # Replace with your repository URL
BRANCH_NAME="feature/x509_enabled"     # Replace with the branch you want to checkout
AWS_ACCESS_KEY_ID="$Accesskey" # Replace with your AWS access key
AWS_SECRET_ACCESS_KEY="$Secretkey" # Replace with your AWS secret key
AWS_DEFAULT_REGION="us-east-1" # Replace with your AWS region
ZIP_FILE="certs.zip" # Replace with the zip file name
S3_BUCKET="s3://symphonydistro/mongo/customer"
CUSTOMER_NAME="$Customer_name" # Replace with the customer name
MONGO_VERSION="v6.0.12" # Replace with the MongoDB version
# ECR_REPOSITORY="$Ecr_repository" # Replace with the ECR repository name
LOG_FILE="mongo_cert_creation_$CUSTOMER_NAME"
LOG_FILE_PATH="/var/log/$LOG_FILE.log"  # Change this path if needed

# # Ensure the log file exists and set proper permissions
# touch "$LOG_FILE_PATH"
# chmod 644 "$LOG_FILE_PATH"

# Function to execute commands silently
execute_command() {
    local command="$1"
    eval "$command"  >> "$LOG_FILE_PATH" 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: Command failed - $command. Check logs at $LOG_FILE_PATH"
        exit 1
    fi
}

# Create a Working directory
mkdir -p /home/"$CUSTOMER_NAME"  >> "$LOG_FILE_PATH" 2>&1
cd /home/"$CUSTOMER_NAME"  >> "$LOG_FILE_PATH" 2>&1

# Export AWS credentials
export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION

# Set up cleanup function
cleanup() {
    cd /home  >> "$LOG_FILE_PATH" 2>&1
    rm -rf "$CUSTOMER_NAME"  >> "$LOG_FILE_PATH" 2>&1
}
trap cleanup EXIT

echo "Starting script at $(date)"

# Clone the Git repository
git clone "$REPO_URL"  >> "$LOG_FILE_PATH" 2>&1
REPO_NAME=$(basename "$REPO_URL" .git)  >> "$LOG_FILE_PATH" 2>&1
cd "$REPO_NAME"  >> "$LOG_FILE_PATH" 2>&1
echo "Current directory: $(pwd)"  >> "$LOG_FILE_PATH" 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to clone the repository. Check logs at $LOG_FILE_PATH"
    exit 1
else
    echo "Repo cloning successful."
fi

# Checkout the specified branch
git checkout "$BRANCH_NAME"  >> "$LOG_FILE_PATH" 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to checkout the branch. Check logs at $LOG_FILE_PATH"
    exit 1
else
    echo "Branch checkout successful."
fi

# Generate certificates
openssl genpkey -algorithm RSA -out certs/ca/ca.key -aes256 -pass pass:test
openssl req -x509 -new -nodes -key certs/ca/ca.key -sha256 -days 365 -config certs/ca/ca.cnf -out certs/ca/ca.pem -passin pass:test
if [ $? -ne 0 ]; then
    echo "Error: Failed to generate CA certificates. Check logs at $LOG_FILE_PATH"
    exit 1
else
    echo "CA certificates generated."
fi

openssl genpkey -algorithm RSA -out certs/server/server.key
openssl req -new -key certs/server/server.key -out certs/server/server.csr -config certs/server/server.cnf
openssl x509 -req -in certs/server/server.csr -CA certs/ca/ca.pem -CAkey certs/ca/ca.key -CAcreateserial -out certs/server/server.crt -days 365 -sha256 -extensions req_ext -extfile certs/server/server.cnf -passin pass:test
cat certs/server/server.key certs/server/server.crt > certs/server/server.pem
if [ $? -ne 0 ]; then
    echo "Error: Failed to generate server certificates. Check logs at $LOG_FILE_PATH"
    exit 1
else
    echo "Server certificates generated."
fi

openssl genpkey -algorithm RSA -out certs/clients/admin/admin.key
openssl req -new -key certs/clients/admin/admin.key -out certs/clients/admin/admin.csr -config certs/clients/admin/admin.cnf
openssl x509 -req -in certs/clients/admin/admin.csr -CA certs/ca/ca.pem -CAkey certs/ca/ca.key -CAcreateserial -out certs/clients/admin/admin.crt -days 365 -sha256 -extensions req_ext -extfile certs/clients/admin/admin.cnf -passin pass:test >> "$LOG_FILE_PATH" 2>&1
cat certs/clients/admin/admin.key certs/clients/admin/admin.crt > certs/clients/admin/admin.pem
if [ $? -ne 0 ]; then
    echo "Error: Failed to generate admin certificates. Check logs at $LOG_FILE_PATH"
    exit 1
else
    echo "Admin certificates generated."
fi

openssl genpkey -algorithm RSA -out certs/clients/symphony/symphony.key
openssl req -new -key certs/clients/symphony/symphony.key -out certs/clients/symphony/symphony.csr -config certs/clients/symphony/symphony.cnf
openssl x509 -req -in certs/clients/symphony/symphony.csr -CA certs/ca/ca.pem -CAkey certs/ca/ca.key -CAcreateserial -out certs/clients/symphony/symphony.crt -days 365 -sha256 -extensions req_ext -extfile certs/clients/symphony/symphony.cnf -passin pass:test
cat certs/clients/symphony/symphony.key certs/clients/symphony/symphony.crt > certs/clients/symphony/symphony.pem
if [ $? -ne 0 ]; then
    echo "Error: Failed to generate Symphony certificates. Check logs at $LOG_FILE_PATH"
    exit 1
else
    echo "Symphony certificates generated."
fi
cat certs/clients/symphony/symphony.pem >> "$LOG_FILE_PATH" 2>&1
aws s3 cp certs/clients/symphony/symphony.pem "$S3_BUCKET/$CUSTOMER_NAME/certs/mongodb.pem"  >> "$LOG_FILE_PATH" 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to upload Symphony certificate to S3. Check logs at $LOG_FILE_PATH"
    exit 1
else
    echo "Symphony certificate uploaded to S3."
fi

# Zip the certificates
zip -r "$ZIP_FILE" certs/  >> "$LOG_FILE_PATH" 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to zip the certificates. Check logs at $LOG_FILE_PATH"
    exit 1
else
    echo "Certificates zipped."
fi

# Upload to S3
aws s3 cp "$ZIP_FILE" "$S3_BUCKET/$CUSTOMER_NAME/certs/"  >> "$LOG_FILE_PATH" 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to upload certificates to S3. Check logs at $LOG_FILE_PATH"
    exit 1
else
    echo "Certificates uploaded to S3."
fi

# Upload CA and Symphony certificates to S3
cat certs/ca/ca.pem >> "$LOG_FILE_PATH" 2>&1
aws s3 cp certs/ca/ca.pem "$S3_BUCKET/$CUSTOMER_NAME/certs/rootCA.pem" >> "$LOG_FILE_PATH" 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to upload CA certificate to S3. Check logs at $LOG_FILE_PATH"
    exit 1
else
    echo "CA certificate uploaded to S3."
fi

# Build the Docker image
docker build --no-cache -t "$CUSTOMER_NAME:mongo$MONGO_VERSION" .  >> "$LOG_FILE_PATH" 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to build the Docker image. Check logs at $LOG_FILE_PATH"
    exit 1
else
    echo "Docker image built successfully."
fi

# Save the Docker image as a tar file
docker save -o "${CUSTOMER_NAME}_mongo_${MONGO_VERSION}.tar" "$CUSTOMER_NAME:mongo$MONGO_VERSION"  >> "$LOG_FILE_PATH" 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to save the Docker image as a tar file. Check logs at $LOG_FILE_PATH"
    exit 1
else
    echo "Docker image saved as a tar file."
fi

# Step 10: Upload the tar file to S3
aws s3 cp "${CUSTOMER_NAME}_mongo_${MONGO_VERSION}.tar" "$S3_BUCKET/$CUSTOMER_NAME/images/mongo_${MONGO_VERSION}.tar"  >> "$LOG_FILE_PATH" 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to upload the Docker image to S3. Check logs at $LOG_FILE_PATH"
    exit 1
else
    echo "Docker image uploaded to S3."
fi
# cleanup locally saved tar file and mongo image
docker rmi "$CUSTOMER_NAME:mongo$MONGO_VERSION"  >> "$LOG_FILE_PATH" 2>&1
rm -rf "${CUSTOMER_NAME}_mongo_${MONGO_VERSION}.tar"  >> "$LOG_FILE_PATH" 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to cleanup the Docker image. Check logs at $LOG_FILE_PATH"
    exit 1
else
    echo "Docker image cleanup successful."
    echo "MongoDB certificate automation script completed successfully."
fi

# # Step 11: Login to AWS ECR
# aws ecr get-login-password --region "$AWS_DEFAULT_REGION" | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com"  >> "$LOG_FILE_PATH" 2>&1
# step_done "Logged into AWS ECR."

# # Step 12: Check and create ECR repository if not exists
# REPO_CHECK=$(aws ecr describe-repositories --region "$AWS_DEFAULT_REGION" --repository-names "$ECR_REPOSITORY" 2>/dev/null)
# if [ $? -ne 0 ]; then
#     aws ecr create-repository --region "$AWS_DEFAULT_REGION" --repository-name "$ECR_REPOSITORY"  >> "$LOG_FILE_PATH" 2>&1
#     step_done "ECR repository $ECR_REPOSITORY created."
# else
#     step_done "ECR repository $ECR_REPOSITORY already exists."
# fi

# # Step 13: Push the Docker image to ECR
# FULL_ECR_TAG="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ECR_REPOSITORY}:mongo$MONGO_VERSION"
# docker tag "$CUSTOMER_NAME:mongo$MONGO_VERSION" "$FULL_ECR_TAG"  >> "$LOG_FILE_PATH" 2>&1
# docker push "$FULL_ECR_TAG"  >> "$LOG_FILE_PATH" 2>&1
# step_done "Docker image pushed to ECR."
