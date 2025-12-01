#!/bin/bash
set -e

REGION="eu-west-1"
APP_NAME="film-recommender-final"
ECR_REPO="film-recommender"
LAMBDA_STACK="$APP_NAME-lambda"
ENV_NAME="$APP_NAME-env"
SOLUTION_STACK="64bit Amazon Linux 2023 v4.7.2 running Docker"
MONITORING_INTERVAL=20
MAX_MONITORING_CYCLES=60

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
if [ -z "$ACCOUNT_ID" ]; then
    echo "=================================================="
    echo " ERRORE: Impossibile recuperare l'ID Account AWS. Verifica le tue credenziali."
    echo "=================================================="
    exit 1
fi
S3_BUCKET="elasticbeanstalk-$REGION-$ACCOUNT_ID"

echo "=================================================="
echo " 🚀 DEPLOY ELASTIC BEANSTALK - VERSIONE DEFINITIVA"
echo "=================================================="
echo " REGIONE: $REGION"
echo " ACCOUNT: $ACCOUNT_ID"
echo " APPLICAZIONE: $APP_NAME"
echo " AMBIENTE: $ENV_NAME"
echo "--------------------------------------------------"

# 1. CREA BUCKET S3 PER ELASTIC BEANSTALK
echo "1. Creazione bucket S3 per Elastic Beanstalk..."
if ! aws s3 ls "s3://$S3_BUCKET" --region $REGION &>/dev/null; then
    echo " - Creazione bucket: $S3_BUCKET"
    aws s3 mb "s3://$S3_BUCKET" --region $REGION
    echo " ✅ Bucket creato con successo"
else
    echo " ✅ Bucket già esistente: $S3_BUCKET"
fi

# 2. VERIFICA APPLICAZIONE EB
echo "2. Verifica applicazione Elastic Beanstalk..."
if ! aws elasticbeanstalk describe-applications --application-name "$APP_NAME" --region $REGION &>/dev/null; then
    echo " ❌ Applicazione non trovata, creazione..."
    aws elasticbeanstalk create-application \
        --application-name "$APP_NAME" \
        --region $REGION
    echo " ✅ Applicazione creata"
    sleep 5
else
    echo " ✅ Applicazione trovata: $APP_NAME"
fi

# 3. CONFIGURAZIONE IAM ROLES
echo "3. Configurazione ruoli IAM..."

# Service Role
echo " > Configurazione Service Role..."
if ! aws iam get-role --role-name aws-elasticbeanstalk-service-role --region $REGION &>/dev/null; then
    echo " > Creazione Service Role..."
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
    echo " ✅ Service Role creato"
fi

echo " > Attacco policy al Service Role..."
aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-service-role \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkEnhancedHealth \
    2>/dev/null || echo " [INFO] Policy già attaccata"

aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-service-role \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkService \
    2>/dev/null || echo " [INFO] Policy già attaccata"

# EC2 Instance Profile
echo " > Configurazione EC2 Instance Profile..."
if ! aws iam get-role --role-name aws-elasticbeanstalk-ec2-role --region $REGION &>/dev/null; then
    echo " > Creazione EC2 Role..."
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
    echo " ✅ EC2 Role creato"
fi

if ! aws iam get-instance-profile --instance-profile-name aws-elasticbeanstalk-ec2-role --region $REGION &>/dev/null; then
    aws iam create-instance-profile --instance-profile-name aws-elasticbeanstalk-ec2-role
    sleep 5
    aws iam add-role-to-instance-profile --instance-profile-name aws-elasticbeanstalk-ec2-role --role-name aws-elasticbeanstalk-ec2-role
    echo " ✅ Instance Profile creato e associato"
fi

# Policy per EC2 Role
echo " > Attacco policy al EC2 Role..."
aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-ec2-role \
    --policy-arn arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier \
    2>/dev/null || echo " [INFO] Policy WebTier già attaccata"

aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-ec2-role \
    --policy-arn arn:aws:iam::aws:policy/AWSElasticBeanstalkMulticontainerDocker \
    2>/dev/null || echo " [INFO] Policy MulticontainerDocker già attaccata"

aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-ec2-role \
    --policy-arn arn:aws:iam::aws:policy/AWSElasticBeanstalkWorkerTier \
    2>/dev/null || echo " [INFO] Policy WorkerTier già attaccata"

echo " > Attesa propagazione IAM (15s)..."
sleep 15

# 4. SETUP ECR
echo "4. Setup ECR e Docker..."

if ! aws ecr describe-repositories --repository-names $ECR_REPO --region $REGION &>/dev/null; then
    echo " > Creazione repository ECR: $ECR_REPO"
    aws ecr create-repository --repository-name $ECR_REPO --region $REGION
    echo " ✅ Repository ECR creato"
else
    echo " ✅ Repository ECR già esistente"
fi

ECR_URL=$(aws ecr describe-repositories --repository-names $ECR_REPO --region $REGION --query 'repositories[0].repositoryUri' --output text)
echo " > ECR Repository URI: $ECR_URL"

echo " > Login a ECR..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_URL
echo " ✅ Login ECR riuscito"

echo " > Build e push immagine Docker..."
docker build -t $ECR_REPO .
docker tag $ECR_REPO:latest $ECR_URL:latest
docker push $ECR_URL:latest
echo " ✅ Immagine Docker pushata su ECR"

# 5. PREPARAZIONE DEPLOY EB
echo "5. Preparazione deploy Elastic Beanstalk..."

# Crea .ebextensions
rm -rf .ebextensions
mkdir -p .ebextensions

echo " > Generazione dockerrun.aws.json..."
cat > dockerrun.aws.json <<EOL
{
  "AWSEBDockerrunVersion": 1,
  "Image": {
    "Name": "$ECR_URL:latest",
    "Update": true
  },
  "Ports": [
    {
      "ContainerPort": 8000
    }
  ]
}
EOL

echo " > Generazione .ebextensions/01-app.config..."
cat > .ebextensions/01-app.config <<EOL
option_settings:
  - namespace: aws:elasticbeanstalk:application:environment
    option_name: AWS_REGION
    value: $REGION
  - namespace: aws:elasticbeanstalk:application:environment
    option_name: FLASK_ENV
    value: production
  - namespace: aws:elasticbeanstalk:application:environment
    option_name: API_GATEWAY_URL
    value: https://5rg1b8g2n4.execute-api.eu-west-1.amazonaws.com/Prod
  - namespace: aws:elasticbeanstalk:cloudwatch:logs
    option_name: StreamLogs
    value: true
  - namespace: aws:elasticbeanstalk:cloudwatch:logs
    option_name: RetentionInDays
    value: 7
  - namespace: aws:elasticbeanstalk:environment:process:default
    option_name: HealthCheckPath
    value: /worker/health
EOL

echo " > Creazione package EB..."
rm -f "$APP_NAME.zip"
zip -r "$APP_NAME.zip" dockerrun.aws.json .ebextensions/
echo " ✅ Package ZIP creato: $APP_NAME.zip"

echo " > Upload su S3..."
aws s3 cp "$APP_NAME.zip" "s3://$S3_BUCKET/$APP_NAME.zip"
echo " ✅ Upload completato su S3"

VERSION_LABEL="v-$(date +%Y%m%d%H%M%S)"

echo " > Creazione versione applicazione: $VERSION_LABEL"
aws elasticbeanstalk create-application-version \
  --application-name "$APP_NAME" \
  --region "$REGION" \
  --version-label "$VERSION_LABEL" \
  --source-bundle S3Bucket="$S3_BUCKET",S3Key="$APP_NAME.zip"
echo " ✅ Versione applicazione creata"

# 6. DEPLOY AMBIENTE
echo "6. Deploy ambiente Elastic Beanstalk..."

ENV_INFO=$(aws elasticbeanstalk describe-environments --application-name "$APP_NAME" --environment-names "$ENV_NAME" --region "$REGION" --query 'Environments[0]' --output json 2>/dev/null || echo "{}")
ENV_STATUS=$(echo "$ENV_INFO" | jq -r .Status 2>/dev/null || echo "NOT_EXIST")

if [[ "$ENV_STATUS" == "Ready" || "$ENV_STATUS" == "Updating" || "$ENV_STATUS" == "Launching" ]]; then
  echo " > Aggiornamento ambiente esistente: $ENV_NAME"
  aws elasticbeanstalk update-environment \
    --application-name "$APP_NAME" \
    --environment-name "$ENV_NAME" \
    --version-label "$VERSION_LABEL" \
    --option-settings Namespace=aws:autoscaling:launchconfiguration,OptionName=IamInstanceProfile,Value=aws-elasticbeanstalk-ec2-role \
    --region "$REGION"
else
  echo " > Creazione nuovo ambiente: $ENV_NAME"
  
  if [[ "$ENV_STATUS" == "Terminated" ]]; then
    echo " > Pulizia ambiente terminato..."
    aws elasticbeanstalk delete-environment --environment-name "$ENV_NAME" --region "$REGION" 2>/dev/null || true
    sleep 10
  fi
  
  aws elasticbeanstalk create-environment \
    --application-name "$APP_NAME" \
    --environment-name "$ENV_NAME" \
    --solution-stack-name "$SOLUTION_STACK" \
    --version-label "$VERSION_LABEL" \
    --option-settings \
        Namespace=aws:elasticbeanstalk:environment,OptionName=EnvironmentType,Value=SingleInstance \
        Namespace=aws:autoscaling:launchconfiguration,OptionName=InstanceType,Value=t3.micro \
        Namespace=aws:elasticbeanstalk:environment,OptionName=ServiceRole,Value=aws-elasticbeanstalk-service-role \
        Namespace=aws:autoscaling:launchconfiguration,OptionName=IamInstanceProfile,Value=aws-elasticbeanstalk-ec2-role \
    --region "$REGION"
fi

# 7. MONITORAGGIO DEPLOY
echo "7. Monitoraggio deploy..."
echo " ⏳ Questo potrebbe richiedere 10-15 minuti..."

DEPLOY_SUCCESS=false
for ((i=1; i<=MAX_MONITORING_CYCLES; i++)); do
  ENV_DATA=$(aws elasticbeanstalk describe-environments --application-name "$APP_NAME" --environment-names "$ENV_NAME" --region "$REGION" --query 'Environments[0]' --output json 2>/dev/null || echo "{}")
  STATUS=$(echo "$ENV_DATA" | jq -r .Status 2>/dev/null || echo "UNKNOWN")
  HEALTH=$(echo "$ENV_DATA" | jq -r .Health 2>/dev/null || echo "Grey")
  
  echo " Ciclo $i/$MAX_MONITORING_CYCLES - Stato: $STATUS - Salute: $HEALTH"
  
  if [[ "$STATUS" == "Ready" && "$HEALTH" == "Green" ]]; then
    EB_URL=$(echo "$ENV_DATA" | jq -r .CNAME)
    echo ""
    echo "=================================================="
    echo " ✅ DEPLOY COMPLETATO CON SUCCESSO!"
    echo "=================================================="
    echo " 🌐 URL Applicazione: http://$EB_URL"
    echo " 🔗 API Gateway: https://5rg1b8g2n4.execute-api.eu-west-1.amazonaws.com/Prod"
    echo "--------------------------------------------------"
    echo " 📧 Credenziali di test:"
    echo "    Email: test@filmrecommender.com"
    echo "    Password: Password123!"
    echo "=================================================="
    DEPLOY_SUCCESS=true
    break
  elif [[ "$STATUS" == "Terminated" || "$STATUS" == "Terminating" ]]; then
    echo " ❌ ERRORE: Environment in stato $STATUS"
    echo " Ultimi eventi:"
    aws elasticbeanstalk describe-events --environment-name "$ENV_NAME" --region "$REGION" --max-items 5 --query 'Events[*].Message' --output text 2>/dev/null || echo "Nessun evento disponibile"
    break
  fi
  
  sleep $MONITORING_INTERVAL
done

# 8. PULIZIA
echo "8. Pulizia file temporanei..."
rm -f dockerrun.aws.json "$APP_NAME.zip"
rm -rf .ebextensions
echo " ✅ Pulizia completata"

if [ "$DEPLOY_SUCCESS" = false ]; then
    echo ""
    echo "=================================================="
    echo " ⚠️  DEPLOY IN CORSO O IN STATO INCERTO"
    echo "=================================================="
    echo " Controlla manualmente con:"
    echo " aws elasticbeanstalk describe-environments --application-name $APP_NAME --environment-names $ENV_NAME --region $REGION"
    echo " aws elasticbeanstalk describe-events --environment-name $ENV_NAME --region $REGION"
fi

echo ""
echo "=================================================="
echo " 🎉 DEPLOY ELASTIC BEANSTALK COMPLETATO"
echo "=================================================="