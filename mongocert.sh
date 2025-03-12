#!/bin/bash

# Variables
AWS_ACCOUNT_ID="087273302893"
CERT_DIR="mongo_cert"
CERT_PATH="/home/$CERT_DIR"
BITBUCKET_USERNAME="subash_bcs" # Replace with your Bitbucket username
PAT="$Bitbucket_PAT"   # Replace with your PAT
REPO_URL="https://${BITBUCKET_USERNAME}:${PAT}@bitbucket.org/bcs_team_dev/sym_distro_mongo.git" # Replace with your repository URL
BRANCH_NAME="feature/x509_enabled"     # Replace with the branch you want to checkout
AWS_ACCESS_KEY_ID="$AWS_access_key" # Replace with your AWS access key
AWS_SECRET_ACCESS_KEY="$AWS_secret_key" # Replace with your AWS secret key
AWS_DEFAULT_REGION="us-east-1" # Replace with your AWS region
ZIP_FILE="certs.zip" # Replace with the zip file name
S3_BUCKET="s3://symphonydistro/mongo/customer"
CUSTOMER_NAME="$Customer" # Replace with the customer name
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
    eval "$command" >> "$LOG_FILE_PATH" 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: Command failed - $command. Check logs at $LOG_FILE_PATH"
        exit 1
    fi
}

# Function to display step completion
step_done() {
    echo "$1 ✅"
}

# Export AWS credentials
export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION

# Set up cleanup function
cleanup() {
    rm -rf "$CERT_DIR_PATH"
}
trap cleanup EXIT

echo "Starting MongoDB certificate automation script..."

# Step 1: Create a directory
mkdir -p "$CERT_DIR_PATH" >> "$LOG_FILE" 2>&1
cd "$CERT_DIR_PATH" >> "$LOG_FILE" 2>&1
step_done "Directory created: $CERT_DIR_PATH"

# Step 2: Clone the Git repository
git clone "$REPO_URL" >> "$LOG_FILE" 2>&1
REPO_NAME=$(basename "$REPO_URL" .git) >> "$LOG_FILE" 2>&1
cd "$REPO_NAME" >> "$LOG_FILE" 2>&1
echo "Current directory: $(pwd)" >> "$LOG_FILE" 2>&1
step_done "Repository cloned successfully."

# Step 3: Checkout the specified branch
git checkout "$BRANCH_NAME" >> "$LOG_FILE" 2>&1
step_done "Checked out to branch: $BRANCH_NAME."

# Step 4: Generate certificates
openssl genpkey -algorithm RSA -out certs/ca/ca.key -aes256 -pass pass:test >> "$LOG_FILE" 2>&1
openssl req -x509 -new -nodes -key certs/ca/ca.key -sha256 -days 365 -config certs/ca/ca.cnf -out certs/ca/ca.pem -passin pass:test >> "$LOG_FILE" 2>&1
step_done "CA certificates generated."

openssl genpkey -algorithm RSA -out certs/server/server.key >> "$LOG_FILE" 2>&1
openssl req -new -key certs/server/server.key -out certs/server/server.csr -config certs/server/server.cnf >> "$LOG_FILE" 2>&1
openssl x509 -req -in certs/server/server.csr -CA certs/ca/ca.pem -CAkey certs/ca/ca.key -CAcreateserial -out certs/server/server.crt -days 365 -sha256 -extensions req_ext -extfile certs/server/server.cnf -passin pass:test >> "$LOG_FILE" 2>&1
cat certs/server/server.key certs/server/server.crt > certs/server/server.pem >> "$LOG_FILE" 2>&1
step_done "Server certificates generated."

openssl genpkey -algorithm RSA -out certs/clients/admin/admin.key >> "$LOG_FILE" 2>&1
openssl req -new -key certs/clients/admin/admin.key -out certs/clients/admin/admin.csr -config certs/clients/admin/admin.cnf >> "$LOG_FILE" 2>&1
openssl x509 -req -in certs/clients/admin/admin.csr -CA certs/ca/ca.pem -CAkey certs/ca/ca.key -CAcreateserial -out certs/clients/admin/admin.crt -days 365 -sha256 -extensions req_ext -extfile certs/clients/admin/admin.cnf -passin pass:test >> "$LOG_FILE" 2>&1
cat certs/clients/admin/admin.key certs/clients/admin/admin.crt > certs/clients/admin/admin.pem >> "$LOG_FILE" 2>&1
step_done "Admin certificates generated."

openssl genpkey -algorithm RSA -out certs/clients/symphony/symphony.key >> "$LOG_FILE" 2>&1
openssl req -new -key certs/clients/symphony/symphony.key -out certs/clients/symphony/symphony.csr -config certs/clients/symphony/symphony.cnf  >> "$LOG_FILE" 2>&1
openssl x509 -req -in certs/clients/symphony/symphony.csr -CA certs/ca/ca.pem -CAkey certs/ca/ca.key -CAcreateserial -out certs/clients/symphony/symphony.crt -days 365 -sha256 -extensions req_ext -extfile certs/clients/symphony/symphony.cnf -passin pass:test >> "$LOG_FILE" 2>&1
cat certs/clients/symphony/symphony.key certs/clients/symphony/symphony.crt > certs/clients/symphony/symphony.pem >> "$LOG_FILE" 2>&1
step_done "Symphony certificates generated."

# Step 5: Zip the certificates
zip -r "$ZIP_FILE" certs/ >> "$LOG_FILE" 2>&1
step_done "Certificates zipped."

# Step 6: Upload to S3
aws s3 cp "$ZIP_FILE" "$S3_BUCKET/$CUSTOMER_NAME/certs/" >> "$LOG_FILE" 2>&1
step_done "Zip file uploaded to S3."

# Step 7: Upload CA and Symphony certificates to S3
aws s3 cp certs/ca/ca.pem "$S3_BUCKET/$CUSTOMER_NAME/key/rootCA.pem" >> "$LOG_FILE" 2>&1
step_done "CA certificate uploaded to S3."

aws s3 cp certs/clients/symphony/symphony.pem "$S3_BUCKET/$CUSTOMER_NAME/key/mongodb.pem" >> "$LOG_FILE" 2>&1
step_done "Symphony certificate uploaded to S3."

# Step 8: Build the Docker image
docker build --no-cache -t "$CUSTOMER_NAME:mongo$MONGO_VERSION" . >> "$LOG_FILE" 2>&1
step_done "MongoDB Docker image built."

# Step 9: Save the Docker image as a tar file
docker save -o "${CUSTOMER_NAME}_mongo_${MONGO_VERSION}.tar" "$CUSTOMER_NAME:mongo$MONGO_VERSION" >> "$LOG_FILE" 2>&1
step_done "Docker image saved as tar file."

# Step 10: Upload the tar file to S3
aws s3 cp "${CUSTOMER_NAME}_mongo_${MONGO_VERSION}.tar" "$S3_BUCKET/$CUSTOMER_NAME/images/" >> "$LOG_FILE" 2>&1
step_done "Mongo tar file uploaded to S3."

# # Step 11: Login to AWS ECR
# aws ecr get-login-password --region "$AWS_DEFAULT_REGION" | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com" >> "$LOG_FILE" 2>&1
# step_done "Logged into AWS ECR."

# # Step 12: Check and create ECR repository if not exists
# REPO_CHECK=$(aws ecr describe-repositories --region "$AWS_DEFAULT_REGION" --repository-names "$ECR_REPOSITORY" 2>/dev/null)
# if [ $? -ne 0 ]; then
#     aws ecr create-repository --region "$AWS_DEFAULT_REGION" --repository-name "$ECR_REPOSITORY" >> "$LOG_FILE" 2>&1
#     step_done "ECR repository $ECR_REPOSITORY created."
# else
#     step_done "ECR repository $ECR_REPOSITORY already exists."
# fi

# # Step 13: Push the Docker image to ECR
# FULL_ECR_TAG="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ECR_REPOSITORY}:mongo$MONGO_VERSION"
# docker tag "$CUSTOMER_NAME:mongo$MONGO_VERSION" "$FULL_ECR_TAG" >> "$LOG_FILE" 2>&1
# docker push "$FULL_ECR_TAG" >> "$LOG_FILE" 2>&1
# step_done "Docker image pushed to ECR."

echo "MongoDB certificate creation and deployment completed successfully! 🎉"
