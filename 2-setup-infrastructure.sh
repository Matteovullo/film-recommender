#!/bin/bash
set -e

REGION="eu-west-1"
APP_NAME="film-recommender-final"
LAMBDA_STACK="$APP_NAME-lambda"
COGNITO_USER_POOL_NAME="FilmRecommenderUserPool"
CLIENT_NAME="WebClient"
TEST_USER_EMAIL="test@filmrecommender.com"
TEST_USER_PASSWORD="Password123!"

echo "======================================================"
echo " 🏗️  SETUP INFRASTRUTTURA BASE"
echo "======================================================"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
S3_BUCKET_FULL="film-recommender-pipeline-$ACCOUNT_ID"

# 1. CREA BUCKET S3 PER SAM E PIPELINE
echo "1. Creazione bucket S3 per SAM e pipeline..."
if ! aws s3 ls "s3://$S3_BUCKET_FULL" --region $REGION &>/dev/null; then
    echo " - Creazione bucket: $S3_BUCKET_FULL"
    aws s3 mb "s3://$S3_BUCKET_FULL" --region $REGION
    echo " ✅ Bucket creato con successo"
else
    echo " ✅ Bucket già esistente: $S3_BUCKET_FULL"
fi

# 2. DEPLOY STACK SAM
echo "2. Deploy Stack SAM (Lambda, API Gateway, DynamoDB, SQS)..."
sam build --template-file template.yaml

sam deploy \
    --template-file .aws-sam/build/template.yaml \
    --stack-name $LAMBDA_STACK \
    --s3-bucket $S3_BUCKET_FULL \
    --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND \
    --region $REGION \
    --no-confirm-changeset

# 3. RECUPERA URL API
API_URL=$(aws cloudformation describe-stacks --stack-name $LAMBDA_STACK --region $REGION --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' --output text)
echo " ✅ API Gateway URL: $API_URL"

# 4. CREA COGNITO USER POOL
echo "4. Creazione Cognito User Pool..."
USER_POOL_ID=$(aws cognito-idp create-user-pool \
    --pool-name $COGNITO_USER_POOL_NAME \
    --region $REGION \
    --auto-verified-attributes email \
    --query 'UserPool.Id' --output text)
echo " ✅ User Pool ID: $USER_POOL_ID"

# 5. CREA CLIENT COGNITO
CLIENT_ID=$(aws cognito-idp create-user-pool-client \
    --user-pool-id $USER_POOL_ID \
    --client-name "$CLIENT_NAME" \
    --explicit-auth-flows "ALLOW_USER_PASSWORD_AUTH" "ALLOW_USER_SRP_AUTH" \
    --no-generate-secret --region $REGION \
    --query 'UserPoolClient.ClientId' --output text)
echo " ✅ Client ID: $CLIENT_ID"

# 6. CREA UTENTE TEST
echo "6. Creazione utente test..."
aws cognito-idp admin-create-user \
    --user-pool-id $USER_POOL_ID \
    --username "$TEST_USER_EMAIL" \
    --user-attributes Name="email",Value="$TEST_USER_EMAIL" \
    --temporary-password "$TEST_USER_PASSWORD" \
    --region $REGION > /dev/null

aws cognito-idp admin-set-user-password \
    --user-pool-id $USER_POOL_ID \
    --username "$TEST_USER_EMAIL" \
    --password "$TEST_USER_PASSWORD" \
    --permanent \
    --region $REGION > /dev/null
echo " ✅ Utente test creato: $TEST_USER_EMAIL"

# 7. AGGIORNA CONFIGURAZIONI
echo "7. Aggiornamento configurazioni..."
# Aggiorna auth.js
sed -i.bak "s/const USER_POOL_ID = \".*\";/const USER_POOL_ID = \"$USER_POOL_ID\";/" static/js/auth.js
sed -i.bak "s/const CLIENT_ID = \".*\";/const CLIENT_ID = \"$CLIENT_ID\";/" static/js/auth.js

# Aggiorna application.py
sed -i.bak "s|API_BASE_URL = os.environ.get('API_GATEWAY_URL', '.*')|API_BASE_URL = os.environ.get('API_GATEWAY_URL', '$API_URL')|" application.py

# Aggiorna app.js
sed -i.bak "s|let API_BASE_URL = '.*';|let API_BASE_URL = '$API_URL';|g" static/js/app.js

# Pulisci file backup
find . -name "*.bak" -delete

echo "======================================================"
echo " ✅ INFRASTRUTTURA BASE COMPLETATA"
echo "======================================================"
echo "API URL: $API_URL"
echo "User Pool: $USER_POOL_ID"
echo "Client ID: $CLIENT_ID"
echo "Utente Test: $TEST_USER_EMAIL"
echo "Bucket S3: $S3_BUCKET_FULL"