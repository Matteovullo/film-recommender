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
echo "   📝 Creazione policy custom per EC2 Describe LaunchTemplates..."
aws iam put-role-policy \
    --role-name aws-elasticbeanstalk-ec2-role \
    --policy-name EB-EC2-LaunchTemplate-Permissions \
    --policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "ec2:DescribeLaunchTemplates",
                    "ec2:DescribeLaunchTemplateVersions",
                    "ec2:DescribeImages",
                    "ec2:DescribeInstances",
                    "ec2:DescribeInstanceTypes",
                    "ec2:DescribeSecurityGroups",
                    "ec2:DescribeSubnets",
                    "ec2:DescribeVpcs",
                    "ec2:DescribeVolumes",
                    "ec2:DescribeKeyPairs",
                    "ec2:DescribeTags",
                    "ec2:DescribeAccountAttributes",
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

# 5. DEPLOY STACK SAM (Lambda, API Gateway, DynamoDB) - FIX PER PATH CON SPAZI
echo ""
echo "5. ⚡ DEPLOY STACK SERVERLESS (SAM)..."

echo "   🔨 Building SAM application..."
# Usa un path temporaneo senza spazi per SAM
TEMP_DIR=$(mktemp -d)
cp -r . "$TEMP_DIR/"
cd "$TEMP_DIR"

echo "   🚀 Deploying Lambda stack: $LAMBDA_STACK"
sam deploy \
    --template-file template.yaml \
    --stack-name $LAMBDA_STACK \
    --s3-bucket $S3_BUCKET_FULL \
    --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND \
    --region $REGION \
    --no-confirm-changeset \
    --no-fail-on-empty-changeset

# Torna alla directory originale
cd - > /dev/null

# 6. RECUPERA URL API
echo ""
echo "6. 🔗 RECUPERO URL API GATEWAY..."
API_URL=$(aws cloudformation describe-stacks --stack-name $LAMBDA_STACK --region $REGION --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' --output text 2>/dev/null || echo "")

if [ -n "$API_URL" ] && [ "$API_URL" != "None" ]; then
    echo "   ✅ API Gateway URL: $API_URL"
else
    echo "   ⚠️  API Gateway URL non disponibile"
    API_URL=""
fi

# 7. VERIFICA/CREA COGNITO USER POOL
echo ""
echo "7. 🔐 CONFIGURAZIONE COGNITO USER POOL..."

# Prima cerca se esiste già un User Pool
EXISTING_POOL=$(aws cognito-idp list-user-pools --region $REGION --max-results 20 \
    --query "UserPools[?contains(Name, 'FilmRecommender')].Id" --output text 2>/dev/null || echo "")

if [ -n "$EXISTING_POOL" ]; then
    echo "   ✅ User Pool già esistente: $EXISTING_POOL"
    USER_POOL_ID="$EXISTING_POOL"
    
    # Recupera Client ID esistente
    CLIENT_ID=$(aws cognito-idp list-user-pool-clients \
        --user-pool-id $USER_POOL_ID \
        --region $REGION \
        --query 'UserPoolClients[0].ClientId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$CLIENT_ID" ] && [ "$CLIENT_ID" != "None" ]; then
        echo "   ✅ Client ID già esistente: $CLIENT_ID"
    else
        echo "   ℹ️  Creazione nuovo Client..."
        CLIENT_ID=$(aws cognito-idp create-user-pool-client \
            --user-pool-id $USER_POOL_ID \
            --client-name "$CLIENT_NAME" \
            --explicit-auth-flows "ALLOW_USER_PASSWORD_AUTH" "ALLOW_USER_SRP_AUTH" "ALLOW_REFRESH_TOKEN_AUTH" \
            --no-generate-secret \
            --region $REGION \
            --query 'UserPoolClient.ClientId' --output text)
        echo "   ✅ Nuovo Client ID: $CLIENT_ID"
    fi
else
    echo "   🗂️  Creazione nuovo User Pool..."
    
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

    # Crea Client
    CLIENT_ID=$(aws cognito-idp create-user-pool-client \
        --user-pool-id $USER_POOL_ID \
        --client-name "$CLIENT_NAME" \
        --explicit-auth-flows "ALLOW_USER_PASSWORD_AUTH" "ALLOW_USER_SRP_AUTH" "ALLOW_REFRESH_TOKEN_AUTH" \
        --no-generate-secret \
        --region $REGION \
        --query 'UserPoolClient.ClientId' --output text)

    echo "   ✅ Client ID: $CLIENT_ID"
fi

# 8. CREA UTENTE TEST
echo ""
echo "8. 👤 CREAZIONE UTENTE DI TEST..."
if [ -n "$USER_POOL_ID" ]; then
    # Verifica se l'utente esiste già
    if ! aws cognito-idp admin-get-user \
        --user-pool-id $USER_POOL_ID \
        --username "$TEST_USER_EMAIL" \
        --region $REGION &>/dev/null; then
        
        echo "   📝 Creazione utente test..."
        aws cognito-idp admin-create-user \
            --user-pool-id $USER_POOL_ID \
            --username "$TEST_USER_EMAIL" \
            --user-attributes Name="email",Value="$TEST_USER_EMAIL" Name="email_verified",Value="true" \
            --temporary-password "$TEST_USER_PASSWORD" \
            --message-action SUPPRESS \
            --region $REGION > /dev/null 2>&1 || echo "     ⚠️  Errore creazione utente"

        aws cognito-idp admin-set-user-password \
            --user-pool-id $USER_POOL_ID \
            --username "$TEST_USER_EMAIL" \
            --password "$TEST_USER_PASSWORD" \
            --permanent \
            --region $REGION > /dev/null 2>&1 || echo "     ⚠️  Errore impostazione password"
        
        echo "   ✅ Utente test creato: $TEST_USER_EMAIL / $TEST_USER_PASSWORD"
    else
        echo "   ✅ Utente test già esistente: $TEST_USER_EMAIL"
    fi
else
    echo "   ⚠️  Skippato creazione utente test (User Pool non disponibile)"
fi

# 9. AGGIORNA CONFIGURAZIONI APPLICAZIONE
echo ""
echo "9. 📝 AGGIORNAMENTO CONFIGURAZIONI APPLICAZIONE..."

# Aggiorna application.py con URL API (solo se abbiamo un URL valido)
if [ -f "application.py" ] && [ -n "$API_URL" ]; then
    echo "   🔄 Aggiornamento application.py..."
    # Crea backup
    cp application.py application.py.backup 2>/dev/null || true
    
    # Cerca e sostituisce API_GATEWAY_URL
    if grep -q "API_GATEWAY_URL = " application.py; then
        sed -i.bak "s|API_GATEWAY_URL =.*|API_GATEWAY_URL = '$API_URL'|g" application.py
        echo "     ✅ API Gateway URL aggiornato in application.py"
    else
        # Aggiungi dopo gli imports
        IMPORT_LINE=$(grep -n "^import\|^from" application.py | tail -1 | cut -d: -f1)
        if [ -n "$IMPORT_LINE" ]; then
            sed -i.bak "${IMPORT_LINE}a\\
# API Gateway Configuration
API_GATEWAY_URL = '$API_URL'
" application.py
            echo "     ✅ API Gateway URL aggiunto a application.py"
        fi
    fi
elif [ -f "application.py" ]; then
    echo "   ⚠️  Skippato aggiornamento application.py (URL API non disponibile)"
fi

# Aggiorna app.js con URL API
if [ -f "static/js/app.js" ] && [ -n "$API_URL" ]; then
    echo "   🔄 Aggiornamento app.js..."
    cp static/js/app.js static/js/app.js.backup 2>/dev/null || true
    
    # Cerca diverse forme di API_BASE_URL
    sed -i.bak "s|let API_BASE_URL =.*|let API_BASE_URL = '$API_URL';|g" static/js/app.js
    sed -i.bak "s|const API_BASE_URL =.*|const API_BASE_URL = '$API_URL';|g" static/js/app.js
    sed -i.bak "s|var API_BASE_URL =.*|var API_BASE_URL = '$API_URL';|g" static/js/app.js
    
    echo "     ✅ API URL aggiornato in app.js"
elif [ -f "static/js/app.js" ]; then
    echo "   ⚠️  Skippato aggiornamento app.js (URL API non disponibile)"
fi

# Aggiorna auth.js con Cognito config (solo se abbiamo valori validi)
if [ -f "static/js/auth.js" ] && [ -n "$USER_POOL_ID" ] && [ -n "$CLIENT_ID" ]; then
    echo "   🔄 Aggiornamento auth.js..."
    cp static/js/auth.js static/js/auth.js.backup 2>/dev/null || true
    
    # Aggiorna USER_POOL_ID
    if grep -q "USER_POOL_ID = " static/js/auth.js; then
        sed -i.bak "s|const USER_POOL_ID =.*|const USER_POOL_ID = '$USER_POOL_ID';|g" static/js/auth.js
        echo "     ✅ USER_POOL_ID aggiornato in auth.js"
    else
        # Aggiungi se non esiste
        sed -i.bak "1s|^|const USER_POOL_ID = '$USER_POOL_ID';\n|" static/js/auth.js
        echo "     ✅ USER_POOL_ID aggiunto a auth.js"
    fi
    
    # Aggiorna CLIENT_ID
    if grep -q "CLIENT_ID = " static/js/auth.js; then
        sed -i.bak "s|const CLIENT_ID =.*|const CLIENT_ID = '$CLIENT_ID';|g" static/js/auth.js
        echo "     ✅ CLIENT_ID aggiornato in auth.js"
    else
        # Aggiungi dopo USER_POOL_ID
        sed -i.bak "/USER_POOL_ID = /a\\
const CLIENT_ID = '$CLIENT_ID';" static/js/auth.js
        echo "     ✅ CLIENT_ID aggiunto a auth.js"
    fi
elif [ -f "static/js/auth.js" ]; then
    echo "   ⚠️  Skippato aggiornamento auth.js (valori Cognito non disponibili)"
fi

# Pulisci file backup
find . -name "*.bak" -delete 2>/dev/null || true
find . -name "*.backup" -delete 2>/dev/null || true

# 10. VERIFICA FINALE
echo ""
echo "10. 🔍 VERIFICA FINALE..."

echo "   📋 File aggiornati:"
if [ -f "application.py" ] && [ -n "$API_URL" ] && grep -q "$API_URL" application.py; then
    echo "     ✅ application.py - URL API Gateway configurato"
fi
if [ -f "static/js/app.js" ] && [ -n "$API_URL" ] && grep -q "$API_URL" static/js/app.js; then
    echo "     ✅ app.js - URL API Gateway configurato"
fi
if [ -f "static/js/auth.js" ] && [ -n "$USER_POOL_ID" ] && grep -q "$USER_POOL_ID" static/js/auth.js; then
    echo "     ✅ auth.js - Configurazione Cognito aggiornata"
fi

echo ""
echo "======================================================"
echo " ✅ INFRASTRUTTURA BASE COMPLETATA"
echo "======================================================"
echo ""
echo "📋 SERVIZI CONFIGURATI:"
echo "   ✅ S3 Bucket: $S3_BUCKET_FULL"
echo "   ✅ Elastic Beanstalk App: $APP_NAME"
echo "   ✅ Lambda Stack: $LAMBDA_STACK"
if [ -n "$API_URL" ]; then
    echo "   ✅ API Gateway: $API_URL"
else
    echo "   ⚠️  API Gateway: URL non disponibile"
fi
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
echo "   ✅ AmazonEC2FullAccess - Risolve ec2:DescribeLaunchTemplates"
echo "   ✅ AutoScalingFullAccess - Risolve permessi AutoScaling"
echo ""
echo "🚀 PRONTO PER IL PROSSIMO STEP: ./3-deploy-ecr-and-docker.sh"
echo ""
echo "🔧 COMANDI DI VERIFICA:"
if [ -n "$API_URL" ]; then
    echo "   Test API Gateway: curl $API_URL/api/health"
fi
echo "======================================================"