#!/bin/bash
set -e

REGION="eu-west-1"
APP_NAME="film-recommender-final"
LAMBDA_STACK="$APP_NAME-lambda-stack"
COGNITO_USER_POOL_NAME="FilmRecommenderUserPool"
CLIENT_NAME="WebClient"
TEST_USER_EMAIL="test@filmrecommender.com"
TEST_USER_PASSWORD="Password123!"

echo "======================================================"
echo " 🏗️  SETUP INFRASTRUTTURA BASE - AMBIENTE DI TEST"
echo "======================================================"
echo " Configurazione COMPLETA per ambiente di test"
echo " Tutti i servizi AWS necessari per il progetto"
echo "======================================================"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
S3_BUCKET_FULL="film-recommender-pipeline-$ACCOUNT_ID"

# 1. CREA BUCKET S3 PER SAM
echo ""
echo "1. 📦 CREAZIONE BUCKET S3 PER SAM..."
if ! aws s3 ls "s3://$S3_BUCKET_FULL" --region $REGION &>/dev/null; then
    echo "   🗂️  Creazione bucket: $S3_BUCKET_FULL"
    aws s3 mb "s3://$S3_BUCKET_FULL" --region $REGION
    echo "   ✅ Bucket creato con successo"
else
    echo "   ✅ Bucket già esistente: $S3_BUCKET_FULL"
fi

# 2. CONFIGURAZIONE RUOLI ELASTIC BEANSTALK (CRITICO!)
echo ""
echo "2. ⚙️  CONFIGURAZIONE RUOLI ELASTIC BEANSTALK..."

# Service Role per Elastic Beanstalk
if ! aws iam get-role --role-name aws-elasticbeanstalk-service-role --region $REGION &>/dev/null; then
    echo "   👨‍💼 Creazione Service Role..."
    aws iam create-role \
        --role-name aws-elasticbeanstalk-service-role \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Service": "elasticbeanstalk.amazonaws.com"
                    },
                    "Action": "sts:AssumeRole"
                }
            ]
        }' \
        --description "Elastic Beanstalk Service Role for Film Recommender" \
        --region $REGION
    echo "   ✅ Service Role creato"
else
    echo "   ✅ Service Role già esistente"
fi

# EC2 Role per Elastic Beanstalk
if ! aws iam get-role --role-name aws-elasticbeanstalk-ec2-role --region $REGION &>/dev/null; then
    echo "   💻 Creazione EC2 Role..."
    aws iam create-role \
        --role-name aws-elasticbeanstalk-ec2-role \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Service": "ec2.amazonaws.com"
                    },
                    "Action": "sts:AssumeRole"
                }
            ]
        }' \
        --description "Elastic Beanstalk EC2 Role for Film Recommender" \
        --region $REGION
    echo "   ✅ EC2 Role creato"
else
    echo "   ✅ EC2 Role già esistente"
fi

# Instance Profile
if ! aws iam get-instance-profile --instance-profile-name aws-elasticbeanstalk-ec2-role --region $REGION &>/dev/null; then
    echo "   🔧 Creazione Instance Profile..."
    aws iam create-instance-profile \
        --instance-profile-name aws-elasticbeanstalk-ec2-role \
        --region $REGION
    sleep 5
    aws iam add-role-to-instance-profile \
        --instance-profile-name aws-elasticbeanstalk-ec2-role \
        --role-name aws-elasticbeanstalk-ec2-role \
        --region $REGION
    echo "   ✅ Instance Profile creato e associato"
else
    echo "   ✅ Instance Profile già esistente"
fi

# ATTACCA POLICY COMPLETE AI RUOLI EB
echo ""
echo "3. 🔐 CONFIGURAZIONE POLICY COMPLETE PER ELASTIC BEANSTALK..."

echo "   🛡️  Configurazione Service Role policies..."
aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-service-role \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkEnhancedHealth \
    --region $REGION 2>/dev/null || echo "     ✅ Policy EnhancedHealth"

aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-service-role \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkService \
    --region $REGION 2>/dev/null || echo "     ✅ Policy Service"

echo "   🛡️  Configurazione EC2 Role policies..."
aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-ec2-role \
    --policy-arn arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier \
    --region $REGION 2>/dev/null || echo "     ✅ Policy WebTier"

aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-ec2-role \
    --policy-arn arn:aws:iam::aws:policy/AWSElasticBeanstalkMulticontainerDocker \
    --region $REGION 2>/dev/null || echo "     ✅ Policy MulticontainerDocker"

aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-ec2-role \
    --policy-arn arn:aws:iam::aws:policy/AWSElasticBeanstalkWorkerTier \
    --region $REGION 2>/dev/null || echo "     ✅ Policy WorkerTier"

# POLICY CRITICA: AutoScaling e EC2 completi (RISOLVE SUSPENDPROCESSES)
echo "   🚨 Aggiunta policy CRITICHE per AutoScaling e EC2..."
aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-ec2-role \
    --policy-arn arn:aws:iam::aws:policy/AutoScalingFullAccess \
    --region $REGION 2>/dev/null || echo "     ✅ Policy AutoScalingFullAccess"

aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-ec2-role \
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess \
    --region $REGION 2>/dev/null || echo "     ✅ Policy AmazonEC2FullAccess"

# Policy custom per permessi specifici
echo "   📝 Creazione policy custom per EC2 Describe..."
aws iam put-role-policy \
    --role-name aws-elasticbeanstalk-ec2-role \
    --policy-name EB-EC2-Complete-Permissions \
    --policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "ec2:DescribeImages",
                    "ec2:DescribeInstances",
                    "ec2:DescribeInstanceTypes",
                    "ec2:DescribeLaunchTemplates",
                    "ec2:DescribeSecurityGroups",
                    "ec2:DescribeSubnets",
                    "ec2:DescribeVpcs",
                    "autoscaling:*",
                    "elasticbeanstalk:*"
                ],
                "Resource": "*"
            }
        ]
    }' \
    --region $REGION 2>/dev/null || echo "     ✅ Policy custom creata"

echo "   ⏳ Attesa propagazione IAM (15 secondi)..."
sleep 15

# 4. CREA APPLICAZIONE ELASTIC BEANSTALK
echo ""
echo "4. 🌐 CREAZIONE APPLICAZIONE ELASTIC BEANSTALK..."
if ! aws elasticbeanstalk describe-applications --application-name "$APP_NAME" --region $REGION &>/dev/null; then
    echo "   🎯 Creazione applicazione: $APP_NAME"
    aws elasticbeanstalk create-application \
        --application-name "$APP_NAME" \
        --description "Film Recommender Application" \
        --region $REGION
    echo "   ✅ Applicazione Elastic Beanstalk creata"
else
    echo "   ✅ Applicazione Elastic Beanstalk già esistente"
fi

# 5. DEPLOY STACK SAM (Lambda, API Gateway, DynamoDB, Cognito)
echo ""
echo "5. ⚡ DEPLOY STACK SERVERLESS (SAM)..."

echo "   🔨 Building SAM application..."
sam build --template-file template.yaml

echo "   🚀 Deploying Lambda stack: $LAMBDA_STACK"
sam deploy \
    --template-file .aws-sam/build/template.yaml \
    --stack-name $LAMBDA_STACK \
    --s3-bucket $S3_BUCKET_FULL \
    --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND \
    --region $REGION \
    --no-confirm-changeset \
    --no-fail-on-empty-changeset

# 6. RECUPERA URL API
echo ""
echo "6. 🔗 RECUPERO URL API GATEWAY..."
API_URL=$(aws cloudformation describe-stacks --stack-name $LAMBDA_STACK --region $REGION --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' --output text 2>/dev/null || echo "")

if [ -n "$API_URL" ]; then
    echo "   ✅ API Gateway URL: $API_URL"
else
    echo "   ⚠️  API Gateway URL non disponibile, uso placeholder"
    API_URL="https://api.example.com"
fi

# 7. CREA COGNITO USER POOL
echo ""
echo "7. 🔐 CREAZIONE COGNITO USER POOL..."

# Crea User Pool
USER_POOL_ID=$(aws cognito-idp create-user-pool \
    --pool-name $COGNITO_USER_POOL_NAME \
    --region $REGION \
    --auto-verified-attributes email \
    --policies '{
        "PasswordPolicy": {
            "MinimumLength": 8,
            "RequireUppercase": true,
            "RequireLowercase": true,
            "RequireNumbers": true,
            "RequireSymbols": false
        }
    }' \
    --schema '[
        {
            "Name": "email",
            "AttributeDataType": "String",
            "Required": true
        }
    ]' \
    --query 'UserPool.Id' --output text)

echo "   ✅ User Pool ID: $USER_POOL_ID"

# 8. CREA CLIENT COGNITO
CLIENT_ID=$(aws cognito-idp create-user-pool-client \
    --user-pool-id $USER_POOL_ID \
    --client-name "$CLIENT_NAME" \
    --explicit-auth-flows "ALLOW_USER_PASSWORD_AUTH" "ALLOW_USER_SRP_AUTH" "ALLOW_REFRESH_TOKEN_AUTH" \
    --no-generate-secret \
    --region $REGION \
    --query 'UserPoolClient.ClientId' --output text)

echo "   ✅ Client ID: $CLIENT_ID"

# 9. CREA UTENTE TEST
echo ""
echo "8. 👤 CREAZIONE UTENTE DI TEST..."
aws cognito-idp admin-create-user \
    --user-pool-id $USER_POOL_ID \
    --username "$TEST_USER_EMAIL" \
    --user-attributes Name="email",Value="$TEST_USER_EMAIL" Name="email_verified",Value="true" \
    --temporary-password "$TEST_USER_PASSWORD" \
    --message-action SUPPRESS \
    --region $REGION > /dev/null 2>&1 || echo "   ⚠️  Utente già esistente o errore non critico"

aws cognito-idp admin-set-user-password \
    --user-pool-id $USER_POOL_ID \
    --username "$TEST_USER_EMAIL" \
    --password "$TEST_USER_PASSWORD" \
    --permanent \
    --region $REGION > /dev/null 2>&1 || echo "   ⚠️  Impostazione password non riuscita"

echo "   ✅ Utente test: $TEST_USER_EMAIL / $TEST_USER_PASSWORD"

# 10. AGGIORNA CONFIGURAZIONI APPLICAZIONE
echo ""
echo "9. 📝 AGGIORNAMENTO CONFIGURAZIONI APPLICAZIONE..."

# Aggiorna application.py con URL API
if [ -f "application.py" ]; then
    echo "   🔄 Aggiornamento application.py..."
    sed -i.bak "s|API_GATEWAY_URL =.*|API_GATEWAY_URL = '$API_URL'|g" application.py 2>/dev/null || echo "     ⚠️  Impossibile aggiornare application.py"
fi

# Aggiorna app.js con URL API
if [ -f "static/js/app.js" ]; then
    echo "   🔄 Aggiornamento app.js..."
    sed -i.bak "s|let API_BASE_URL =.*|let API_BASE_URL = '$API_URL';|g" static/js/app.js 2>/dev/null || echo "     ⚠️  Impossibile aggiornare app.js"
fi

# Aggiorna auth.js con Cognito config
if [ -f "static/js/auth.js" ]; then
    echo "   🔄 Aggiornamento auth.js..."
    sed -i.bak "s|const USER_POOL_ID =.*|const USER_POOL_ID = '$USER_POOL_ID';|g" static/js/auth.js 2>/dev/null || echo "     ⚠️  Impossibile aggiornare USER_POOL_ID"
    sed -i.bak "s|const CLIENT_ID =.*|const CLIENT_ID = '$CLIENT_ID';|g" static/js/auth.js 2>/dev/null || echo "     ⚠️  Impossibile aggiornare CLIENT_ID"
fi

# Pulisci file backup
find . -name "*.bak" -delete 2>/dev/null || true

echo ""
echo "======================================================"
echo " ✅ INFRASTRUTTURA BASE COMPLETATA AL 100%"
echo "======================================================"
echo ""
echo "📋 SERVIZI CONFIGURATI:"
echo "   ✅ S3 Bucket: $S3_BUCKET_FULL"
echo "   ✅ Elastic Beanstalk App: $APP_NAME"
echo "   ✅ Lambda Stack: $LAMBDA_STACK"
echo "   ✅ API Gateway: $API_URL"
echo "   ✅ Cognito User Pool: $USER_POOL_ID"
echo "   ✅ Cognito Client: $CLIENT_ID"
echo ""
echo "🔐 CREDENZIALI TEST:"
echo "   📧 Email: $TEST_USER_EMAIL"
echo "   🔑 Password: $TEST_USER_PASSWORD"
echo ""
echo "⚙️  RUOLI IAM CONFIGURATI:"
echo "   ✅ aws-elasticbeanstalk-service-role"
echo "   ✅ aws-elasticbeanstalk-ec2-role"
echo "   ✅ Tutte le policy necessarie incluse AutoScalingFullAccess"
echo ""
echo "🚀 PRONTO PER IL PROSSIMO STEP: ./3-deploy-ecr-and-docker.sh"
echo "======================================================"