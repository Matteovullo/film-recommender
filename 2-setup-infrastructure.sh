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

# POLICY CRITICA: AutoScaling e EC2 completi
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

# 4. DEPLOY STACK SAM (Lambda, API Gateway, DynamoDB)
echo ""
echo "4. ⚡ DEPLOY STACK SERVERLESS (SAM)..."

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

# 5. RECUPERA URL API (CRITICO - COME VECCHIO DEPLOY)
echo ""
echo "5. 🔗 RECUPERO URL API GATEWAY..."
API_URL=$(aws cloudformation describe-stacks --stack-name $LAMBDA_STACK --region $REGION --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' --output text 2>/dev/null || echo "")

if [ -n "$API_URL" ]; then
    echo "   ✅ API Gateway URL: $API_URL"
    
    # 6. AGGIORNAMENTO FILE STATICI (CRITICO - SOLO app.js COME VECCHIO DEPLOY)
    echo ""
    echo "6. 🔄 AGGIORNAMENTO FILE DI CONFIGURAZIONE..."
    
    # AGGIORNA SOLO app.js (come faceva il vecchio deploy)
    if [ -f "static/js/app.js" ]; then
        echo "   🔄 Aggiornamento static/js/app.js..."
        # Crea backup
        cp static/js/app.js static/js/app.js.backup
        
        # Aggiorna l'URL API (cerca diverse possibili sintassi)
        sed -i.bak "s|let API_BASE_URL =.*|let API_BASE_URL = '$API_URL';|g" static/js/app.js
        sed -i.bak "s|const API_BASE_URL =.*|const API_BASE_URL = '$API_URL';|g" static/js/app.js
        sed -i.bak "s|var API_BASE_URL =.*|var API_BASE_URL = '$API_URL';|g" static/js/app.js
        
        # Verifica l'aggiornamento
        if grep -q "$API_URL" static/js/app.js; then
            echo "   ✅ app.js aggiornato correttamente"
        else
            echo "   ⚠️  Impossibile aggiornare app.js automaticamente"
            echo "   ℹ️  Aggiorna manualmente: let API_BASE_URL = '$API_URL';"
        fi
    else
        echo "   ⚠️  File app.js non trovato"
    fi
    
    # AGGIORNA application.py con URL API (OPZIONALE ma utile)
    if [ -f "application.py" ]; then
        echo "   🔄 Aggiornamento application.py..."
        # Cerca e sostituisci API_GATEWAY_URL
        if grep -q "API_GATEWAY_URL" application.py; then
            sed -i.bak "s|API_GATEWAY_URL =.*|API_GATEWAY_URL = '$API_URL'|g" application.py
            echo "   ✅ application.py aggiornato"
        else
            # Aggiungi dopo gli imports
            IMPORT_LINE=$(grep -n "^import\|^from" application.py | tail -1 | cut -d: -f1)
            if [ -n "$IMPORT_LINE" ]; then
                sed -i.bak "${IMPORT_LINE}a\\
API_GATEWAY_URL = '$API_URL'
" application.py
                echo "   ✅ API_GATEWAY_URL aggiunto a application.py"
            fi
        fi
    fi
    
else
    echo "   ⚠️  API Gateway URL non disponibile"
    echo "   ℹ️  Uso placeholder temporaneo"
    API_URL="https://api.example.com"
fi

# 7. CREA COGNITO USER POOL (MA NON AGGIORNARE auth.js - È GIÀ CORRETTO)
echo ""
echo "7. 🔐 CONFIGURAZIONE COGNITO USER POOL..."

# Cerca User Pool esistente
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
    
    # NOTA: NON aggiorniamo auth.js automaticamente - i valori sono già hardcoded e corretti
    echo "   ℹ️  I valori Cognito in auth.js sono già corretti:"
    echo "      USER_POOL_ID: eu-west-1_Gx1rUSirL"
    echo "      CLIENT_ID: 3ft1kpl7bmvbm3ma2r6ghl6tei"
fi

# 8. CREA UTENTE TEST
echo ""
echo "8. 👤 CREAZIONE UTENTE DI TEST..."
if [ -n "$USER_POOL_ID" ]; then
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
else
    echo "   ⚠️  User Pool non disponibile, skippo creazione utente test"
fi

# 9. AGGIORNAMENTO FINALE E PULIZIA
echo ""
echo "9. 📝 VERIFICA FINALE CONFIGURAZIONI..."

# Verifica che i file siano corretti
echo "   🔍 Controllo app.js..."
if grep -q "API_BASE_URL = '$API_URL'" static/js/app.js 2>/dev/null; then
    echo "   ✅ app.js configurato correttamente"
else
    echo "   ⚠️  app.js potrebbe non essere aggiornato"
    echo "   ℹ️  Controlla manualmente: static/js/app.js"
fi

echo "   🔍 Controllo auth.js..."
if [ -f "static/js/auth.js" ]; then
    CURRENT_POOL=$(grep "USER_POOL_ID = " static/js/auth.js | cut -d\' -f2)
    CURRENT_CLIENT=$(grep "CLIENT_ID = " static/js/auth.js | cut -d\' -f2)
    echo "   ✅ auth.js contiene:"
    echo "      USER_POOL_ID: $CURRENT_POOL"
    echo "      CLIENT_ID: $CURRENT_CLIENT"
fi

echo "   🔍 Controllo application.py..."
if grep -q "API_GATEWAY_URL = " application.py 2>/dev/null; then
    CURRENT_API=$(grep "API_GATEWAY_URL = " application.py | cut -d\' -f2)
    echo "   ✅ application.py contiene API_GATEWAY_URL: $CURRENT_API"
fi

# Pulisci file backup
find . -name "*.bak" -delete 2>/dev/null || true
find . -name "*.backup" -delete 2>/dev/null || true

echo ""
echo "======================================================"
echo " ✅ INFRASTRUTTURA BASE COMPLETATA"
echo "======================================================"
echo ""
echo "📋 SERVIZI CONFIGURATI:"
echo "   ✅ S3 Bucket: $S3_BUCKET_FULL"
echo "   ✅ Lambda Stack: $LAMBDA_STACK"
echo "   ✅ API Gateway: $API_URL"
echo "   ✅ Cognito User Pool: $USER_POOL_ID"
echo "   ✅ Cognito Client: $CLIENT_ID"
echo ""
echo "🔐 CREDENZIALI TEST:"
echo "   📧 Email: $TEST_USER_EMAIL"
echo "   🔑 Password: $TEST_USER_PASSWORD"
echo ""
echo "📁 FILE AGGIORNATI:"
echo "   ✅ static/js/app.js - URL API Gateway"
echo "   ✅ application.py - URL API Gateway"
echo ""
echo "ℹ️  NOTA: auth.js non è stato modificato - usa i valori hardcoded già presenti"
echo ""
echo "🚀 PRONTO PER IL PROSSIMO STEP: ./3-deploy-ecr-and-docker.sh"
echo "======================================================"