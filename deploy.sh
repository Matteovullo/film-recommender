#!/bin/bash

set -e

REGION="eu-west-1"
ACCOUNT_ID="023048164072"
APP_NAME="film-recommender-final"
ECR_REPO="film-recommender"
S3_BUCKET="elasticbeanstalk-$REGION-$ACCOUNT_ID"
LAMBDA_STACK="$APP_NAME-lambda"
ENV_NAME="$APP_NAME-env"
SOLUTION_STACK="64bit Amazon Linux 2023 v4.7.2 running Docker"
MONITORING_INTERVAL=20
MAX_MONITORING_CYCLES=60

echo "🎬 FILM RECOMMENDER - DEPLOY COMPLETO E DEFINITIVO"
echo "=================================================="
echo "📍 Region: $REGION"
echo "👤 Account: $ACCOUNT_ID"
echo "📱 App: $APP_NAME"
echo ""

# Check essential files
ESSENTIAL_FILES=("application.py" "requirements.txt" "Dockerfile" "static/html/index.html" "static/js/auth.js")
for file in "${ESSENTIAL_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "❌ File mancante: $file"
        exit 1
    fi
done
echo "✅ Tutti i file essenziali presenti"

# --- DEPLOY LAMBDA (OPZIONALE) ---
if command -v sam &> /dev/null; then
    echo "📦 Building SAM application..."
    sam build
    echo "🚀 Deploying Lambda stack..."
    sam deploy --stack-name $LAMBDA_STACK --capabilities CAPABILITY_IAM --region $REGION --resolve-s3 --no-confirm-changeset --no-fail-on-empty-changeset
    API_URL=$(aws cloudformation describe-stacks --stack-name $LAMBDA_STACK --region $REGION --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' --output text 2>/dev/null || echo "")
    if [ -n "$API_URL" ]; then
        echo "✅ API Gateway: $API_URL"
        echo "🔧 Aggiornamento URL API nei file JavaScript..."
        sed -i.bak "s|let API_BASE_URL =.*|let API_BASE_URL = '$API_URL';|g" static/js/app.js 2>/dev/null || echo "⚠️  Impossibile aggiornare app.js"
        sed -i.bak "s|let API_BASE_URL =.*|let API_BASE_URL = '$API_URL';|g" static/js/dashboard.js 2>/dev/null || echo "⚠️  Impossibile aggiornare dashboard.js"
    else
        echo "⚠️  API Gateway non disponibile"
        API_URL="https://g1q9d4xdfg.execute-api.eu-west-1.amazonaws.com/Prod"
    fi
else
    echo "⚠️  SAM CLI non installato - salto deploy Lambda"
    API_URL="https://g1q9d4xdfg.execute-api.eu-west-1.amazonaws.com/Prod"
fi

# --- SETUP IAM ROLES ---
echo "👮 CONFIGURAZIONE IAM ROLES"

# CREA SERVICE ROLE
echo "📝 Configurazione Service Role..."
if ! aws iam get-role --role-name aws-elasticbeanstalk-service-role --region $REGION &>/dev/null; then
    echo "🔄 Creazione Service Role..."
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
        --description "Elastic Beanstalk Service Role"
    
    echo "✅ Service Role creato"
else
    echo "✅ Service Role già esistente"
fi

# ATTACCA POLICY AL SERVICE ROLE
echo "📎 Attacco policy al Service Role..."
aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-service-role \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkEnhancedHealth \
    2>/dev/null || echo "⚠️  Policy già attaccata"

aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-service-role \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkService \
    2>/dev/null || echo "⚠️  Policy già attaccata"

# CREA EC2 INSTANCE PROFILE
echo "📝 Configurazione EC2 Instance Profile..."
if ! aws iam get-instance-profile --instance-profile-name aws-elasticbeanstalk-ec2-role --region $REGION &>/dev/null; then
    echo "🔄 Creazione EC2 Role..."
    # Crea il ruolo EC2
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
        --description "Elastic Beanstalk EC2 Role"
    
    echo "✅ EC2 Role creato"
    
    # Crea l'instance profile
    aws iam create-instance-profile \
        --instance-profile-name aws-elasticbeanstalk-ec2-role
    
    # Aggiungi il ruolo all'instance profile
    aws iam add-role-to-instance-profile \
        --instance-profile-name aws-elasticbeanstalk-ec2-role \
        --role-name aws-elasticbeanstalk-ec2-role
    
    echo "✅ Instance Profile creato"
else
    echo "✅ Instance Profile già esistente"
fi

# ATTACCA POLICY AL EC2 ROLE
echo "📎 Attacco policy al EC2 Role..."
aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-ec2-role \
    --policy-arn arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier \
    2>/dev/null || echo "⚠️  Policy già attaccata"

aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-ec2-role \
    --policy-arn arn:aws:iam::aws:policy/AWSElasticBeanstalkMulticontainerDocker \
    2>/dev/null || echo "⚠️  Policy già attaccata"

aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-ec2-role \
    --policy-arn arn:aws:iam::aws:policy/AWSElasticBeanstalkWorkerTier \
    2>/dev/null || echo "⚠️  Policy già attaccata"

echo "⏳ Attesa propagazione IAM..."
sleep 10

# --- SETUP ECR ---
echo "🐳 SETUP ECR E DOCKER"

if ! aws ecr describe-repositories --repository-names $ECR_REPO --region $REGION &>/dev/null; then
    echo "📦 Creazione repository ECR: $ECR_REPO"
    aws ecr create-repository --repository-name $ECR_REPO --region $REGION
else
    echo "✅ Repository ECR già esistente"
fi

ECR_URL=$(aws ecr describe-repositories --repository-names $ECR_REPO --region $REGION --query 'repositories[0].repositoryUri' --output text)
echo "📡 ECR Repository: $ECR_URL"

echo "🔐 Login a ECR..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_URL

echo "🐳 Build e push immagine Docker..."
docker build -t $ECR_REPO .
docker tag $ECR_REPO:latest $ECR_URL:latest
docker push $ECR_URL:latest
echo "✅ Immagine Docker pushata su ECR"

# --- CLEANUP DOCKER ---
echo "🧹 Pulizia Docker locale..."
docker container prune -f || true
docker image prune -a -f || true
echo "✅ Pulizia Docker completata"

# --- ELASTIC BEANSTALK ---
echo "⚙️ SETUP ELASTIC BEANSTALK"

# PULIZIA CONFIGURAZIONI
rm -rf .ebextensions
mkdir -p .ebextensions

# DOCKERRUN.aws.json
cat > dockerrun.aws.json << EOL
{
  "AWSEBDockerrunVersion": "1",
  "Image": {
    "Name": "$ECR_URL:latest",
    "Update": "true"
  },
  "Ports": [
    {
      "ContainerPort": "8000"
    }
  ]
}
EOL

# CONFIGURAZIONE MIGLIORATA
cat > .ebextensions/01-app.config << EOL
option_settings:
  aws:elasticbeanstalk:application:environment:
    AWS_REGION: $REGION
    FLASK_ENV: production
    API_GATEWAY_URL: $API_URL
    
  aws:elasticbeanstalk:cloudwatch:logs:
    StreamLogs: true
    RetentionInDays: 7
    
  aws:elasticbeanstalk:environment:process:default:
    HealthCheckPath: /worker/health
    Port: 8000
    Protocol: HTTP
EOL

# CREA/VERIFICA APPLICAZIONE EB
echo "🔄 Creazione/verifica applicazione EB..."
aws elasticbeanstalk create-application \
    --application-name $APP_NAME \
    --region $REGION \
    2>/dev/null && echo "✅ Applicazione EB creata" || echo "⚠️  Applicazione EB già esistente"

sleep 5

# PREPARA E CARICA VERSIONE
echo "📦 Preparazione package EB..."
rm -f $APP_NAME.zip
zip -r $APP_NAME.zip dockerrun.aws.json Dockerfile application.py requirements.txt static/ .ebextensions/ -x "*.git*" "*.DS_Store*" "deploy-*.sh" "*.zip" "*.log" ".aws-sam/*"

echo "📤 Upload su S3..."
aws s3 cp $APP_NAME.zip s3://$S3_BUCKET/$APP_NAME.zip

VERSION_LABEL="v-complete-$(date +%Y%m%d%H%M%S)"
echo "🏷️ Creazione versione: $VERSION_LABEL"

aws elasticbeanstalk create-application-version \
    --application-name $APP_NAME \
    --region $REGION \
    --version-label "$VERSION_LABEL" \
    --source-bundle S3Bucket="$S3_BUCKET",S3Key="$APP_NAME.zip"

echo "✅ Versione applicazione creata"

# VERIFICA SE L'AMBIENTE ESISTE GIA'
echo "🔍 Verifica ambiente esistente..."
ENV_INFO=$(aws elasticbeanstalk describe-environments --application-name $APP_NAME --environment-names "$ENV_NAME" --region $REGION --query 'Environments[0]' --output json 2>/dev/null || echo "{}")
ENV_STATUS=$(echo "$ENV_INFO" | jq -r '.Status // "NOT_FOUND"')

if [ "$ENV_STATUS" = "Ready" ] || [ "$ENV_STATUS" = "Updating" ] || [ "$ENV_STATUS" = "Launching" ]; then
    echo "🔄 Aggiornamento environment esistente: $ENV_NAME"
    aws elasticbeanstalk update-environment \
        --application-name $APP_NAME \
        --environment-name "$ENV_NAME" \
        --version-label "$VERSION_LABEL" \
        --region $REGION
else
    echo "🌱 Creazione nuovo environment: $ENV_NAME"
    
    # Pulisci ambiente terminato se esiste
    if [ "$ENV_STATUS" = "Terminated" ]; then
        echo "🧹 Pulizia ambiente terminato..."
        aws elasticbeanstalk delete-environment \
            --environment-name "$ENV_NAME" \
            --region $REGION \
            2>/dev/null || true
        sleep 10
    fi
    
    echo "🚀 Creazione environment Elastic Beanstalk..."
    aws elasticbeanstalk create-environment \
        --application-name $APP_NAME \
        --environment-name "$ENV_NAME" \
        --solution-stack-name "$SOLUTION_STACK" \
        --version-label "$VERSION_LABEL" \
        --option-settings \
            Namespace=aws:elasticbeanstalk:environment,OptionName=EnvironmentType,Value=SingleInstance \
            Namespace=aws:autoscaling:launchconfiguration,OptionName=InstanceType,Value=t3.micro \
            Namespace=aws:elasticbeanstalk:environment,OptionName=ServiceRole,Value=aws-elasticbeanstalk-service-role \
            Namespace=aws:autoscaling:launchconfiguration,OptionName=IamInstanceProfile,Value=aws-elasticbeanstalk-ec2-role \
        --region $REGION
fi

# --- MONITORAGGIO DEPLOY ---
echo ""
echo "⏳ Monitoraggio deploy (ogni ${MONITORING_INTERVAL}s, max ${MAX_MONITORING_CYCLES} cicli)..."
DEPLOY_SUCCESS=false

for i in $(seq 1 $MAX_MONITORING_CYCLES); do
    ENV_DATA=$(aws elasticbeanstalk describe-environments --application-name $APP_NAME --environment-names "$ENV_NAME" --region $REGION --query 'Environments[0]' --output json 2>/dev/null || echo "{}")
    STATUS=$(echo "$ENV_DATA" | jq -r '.Status // "Unknown"')
    HEALTH=$(echo "$ENV_DATA" | jq -r '.Health // "Unknown"')
    
    echo "   [$i/$MAX_MONITORING_CYCLES] Stato: $STATUS - Salute: $HEALTH"
    
    # Mostra eventi se ci sono problemi
    if [ "$STATUS" = "Launching" ] && [ $i -gt 5 ]; then
        echo "   📋 Eventi recenti:"
        aws elasticbeanstalk describe-events --environment-name "$ENV_NAME" --region $REGION --max-items 2 --query 'Events[].Message' --output text 2>/dev/null | head -1 || echo "   Nessun evento importante"
    fi
    
    if [ "$STATUS" = "Ready" ] && [ "$HEALTH" = "Green" ]; then
        EB_URL=$(echo "$ENV_DATA" | jq -r '.CNAME // ""')
        echo ""
        echo "🎉 DEPLOY COMPLETATO CON SUCCESSO!"
        echo "=================================="
        echo "🌐 URL Applicazione: http://$EB_URL"
        echo "📊 Dashboard: http://$EB_URL/dashboard" 
        echo "🔧 Health Check: http://$EB_URL/worker/health"
        echo "⚡ API Gateway: $API_URL"
        echo ""
        echo "📝 Credenziali di test:"
        echo "   Email: test@filmrecommender.com"
        echo "   Password: Password123"
        echo ""
        echo "🔍 Test rapido:"
        echo "   curl http://$EB_URL/worker/health"
        DEPLOY_SUCCESS=true
        break
    elif [ "$STATUS" = "Terminated" ] || [ "$STATUS" = "Terminating" ]; then
        echo "❌ Environment in stato $STATUS"
        echo "🔍 Ultimi eventi:"
        aws elasticbeanstalk describe-events --environment-name "$ENV_NAME" --region $REGION --max-items 5 --query 'Events[].Message' --output text 2>/dev/null
        break
    fi
    sleep $MONITORING_INTERVAL
done

# --- PULIZIA E REPORT FINALE ---
rm -f $APP_NAME.zip
find static/js/ -name "*.bak" -delete 2>/dev/null || true

echo ""
if [ "$DEPLOY_SUCCESS" = true ]; then
    echo "✅ DEPLOY RIUSCITO!"
    echo "🌐 L'applicazione è disponibile all'URL sopra indicato"
    echo "🔧 Per aggiornamenti futuri, esegui semplicemente: ./deploy.sh"
else
    echo "⚠️  Deploy non completato o in stato incerto"
    echo "📋 Controlla manualmente con:"
    echo "   aws elasticbeanstalk describe-environments --application-name $APP_NAME --environment-names $ENV_NAME --region $REGION"
    echo "   aws elasticbeanstalk describe-events --environment-name $ENV_NAME --region $REGION"
fi

echo ""
echo "✨ Script completato!"