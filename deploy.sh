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
echo " FILM RECOMMENDER - DEPLOY COMPLETO E DEFINITIVO"
echo "=================================================="
echo " REGIONE: $REGION"
echo " ACCOUNT: $ACCOUNT_ID"
echo " APPLICAZIONE: $APP_NAME"
echo "--------------------------------------------------"

# Check essential files
ESSENTIAL_FILES=("application.py" "requirements.txt" "Dockerfile" "static/html/index.html" "static/js/auth.js")
for file in "${ESSENTIAL_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo " [ERRORE] File mancante: $file"
        exit 1
    fi
done
echo " [OK] Tutti i file essenziali presenti"

# --- DEPLOY LAMBDA (SAM) ---
echo "--- DEPLOY SERVIZI SERVERLESS (SAM) ---"

if command -v sam &> /dev/null; then
    echo " > Building SAM application..."
    sam build
    echo " > Deploying Lambda stack ($LAMBDA_STACK)..."
    sam deploy --stack-name $LAMBDA_STACK --capabilities CAPABILITY_IAM --region $REGION --resolve-s3 --no-confirm-changeset --no-fail-on-empty-changeset
    
    API_URL=$(aws cloudformation describe-stacks --stack-name $LAMBDA_STACK --region $REGION --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' --output text 2>/dev/null || echo "")
    
    if [ -n "$API_URL" ]; then
        echo " [OK] API Gateway URL: $API_URL"
        echo " > Aggiornamento URL API nei file JavaScript..."
        sed -i.bak "s|let API_BASE_URL =.*|let API_BASE_URL = '$API_URL';|g" static/js/app.js 2>/dev/null || echo " [ATTENZIONE] Impossibile aggiornare app.js"
        find static/js/ -name "*.bak" -delete 2>/dev/null || true
    else
        echo " [ATTENZIONE] API Gateway URL non disponibile. Uso il placeholder."
        API_URL="https://g1q9d4xdfg.execute-api.eu-west-1.amazonaws.com/Prod"
    fi
else
    echo " [ATTENZIONE] SAM CLI non installato - salto deploy Lambda"
    API_URL="https://g1q9d4xdfg.execute-api.eu-west-1.amazonaws.com/Prod"
fi

# --- CONFIGURAZIONE IAM ---
echo "--------------------------------------------------"
echo "--- CONFIGURAZIONE IAM ROLES ---"

# --- SERVICE ROLE ---
echo " > Configurazione Service Role (aws-elasticbeanstalk-service-role)..."
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
    echo " [OK] Service Role creato"
fi

echo " > Attacco policy al Service Role..."
aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-service-role \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkEnhancedHealth \
    2>/dev/null || echo " [INFO] Policy AWSElasticBeanstalkEnhancedHealth già attaccata"

aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-service-role \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkService \
    2>/dev/null || echo " [INFO] Policy AWSElasticBeanstalkService già attaccata"


# --- EC2 INSTANCE PROFILE (CRITICO PER IL DEPLOY DOCKER) ---
echo " > Configurazione EC2 Instance Profile (aws-elasticbeanstalk-ec2-role)..."
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
    
    echo " [OK] EC2 Role creato"
fi

if ! aws iam get-instance-profile --instance-profile-name aws-elasticbeanstalk-ec2-role --region $REGION &>/dev/null; then
    aws iam create-instance-profile --instance-profile-name aws-elasticbeanstalk-ec2-role
    sleep 5
    aws iam add-role-to-instance-profile --instance-profile-name aws-elasticbeanstalk-ec2-role --role-name aws-elasticbeanstalk-ec2-role
    echo " [OK] Instance Profile creato e associato"
fi


# --- ATTACCO POLICY ALL'EC2 ROLE (RISOLUZIONE BLOCCO EC2:Describe) ---
echo " > Attacco policy al EC2 Role (risoluzione Describe errors)..."

# Policy gestite standard
aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-ec2-role \
    --policy-arn arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier \
    2>/dev/null || echo " [INFO] Policy AWSElasticBeanstalkWebTier già attaccata"

aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-ec2-role \
    --policy-arn arn:aws:iam::aws:policy/AWSElasticBeanstalkMulticontainerDocker \
    2>/dev/null || echo " [INFO] Policy AWSElasticBeanstalkMulticontainerDocker già attaccata"

aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-ec2-role \
    --policy-arn arn:aws:iam::aws:policy/AWSElasticBeanstalkWorkerTier \
    2>/dev/null || echo " [INFO] Policy AWSElasticBeanstalkWorkerTier già attaccata"

# Policy custom EC2 richieste (AGGIUNTA CRITICA per Amazon Linux 2023)
# Risolve ec2:DescribeLaunchTemplates e ec2:DescribeImages
aws iam put-role-policy \
  --role-name aws-elasticbeanstalk-ec2-role \
  --policy-name custom-eb-ec2-describe-permissions \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeLaunchTemplates", 
        "ec2:DescribeImages",         
        "ec2:DescribeInstances",      
        "ec2:DescribeTags"
      ],
      "Resource": "*"
    }]
  }' \
  --region "$REGION"

echo " > Attesa propagazione IAM (30s)..."
sleep 30

# --- SETUP ECR ---
echo "--------------------------------------------------"
echo "--- SETUP ECR E DOCKER ---"

if ! aws ecr describe-repositories --repository-names $ECR_REPO --region $REGION &>/dev/null; then
    echo " > Creazione repository ECR: $ECR_REPO"
    aws ecr create-repository --repository-name $ECR_REPO --region $REGION
    echo " [OK] Repository ECR creato"
else
    echo " [OK] Repository ECR già esistente"
fi

ECR_URL=$(aws ecr describe-repositories --repository-names $ECR_REPO --region $REGION --query 'repositories[0].repositoryUri' --output text)
echo " > ECR Repository URI: $ECR_URL"

echo " > Login a ECR..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_URL
echo " [OK] Login Succeeded"

echo " > Build e push immagine Docker..."
docker build -t $ECR_REPO .
docker tag $ECR_REPO:latest $ECR_URL:latest
docker push $ECR_URL:latest
echo " [OK] Immagine Docker pushata su ECR"

echo " > Pulizia Docker locale..."
docker container prune -f || true
docker image prune -a -f || true
echo " [OK] Pulizia Docker completata"

# --- ELASTIC BEANSTALK CONFIG AND DEPLOYMENT (FORSE CONFLITTO CON PIPELINE) ---
echo "--------------------------------------------------"
echo "--- SETUP ELASTIC BEANSTALK ---"

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

echo " > Generazione .ebextensions/01-app.config (Correzione Static Files)..."
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
    value: $API_URL
  - namespace: aws:elasticbeanstalk:cloudwatch:logs
    option_name: StreamLogs
    value: true
  - namespace: aws:elasticbeanstalk:cloudwatch:logs
    option_name: RetentionInDays
    value: 7
  - namespace: aws:elasticbeanstalk:environment:process:default
    option_name: HealthCheckPath
    value: /worker/health
    option_name: Port
    value: 8000
    option_name: Protocol
    value: HTTP
EOL

echo " > Creazione/verifica applicazione EB..."
aws elasticbeanstalk create-application --application-name "$APP_NAME" --region "$REGION" 2>/dev/null || echo " [OK] Applicazione EB già esistente"
sleep 5
echo " > Preparazione package EB..."
rm -f "$APP_NAME.zip"
zip -r "$APP_NAME.zip" dockerrun.aws.json Dockerfile application.py requirements.txt static .ebextensions -x "*.git*" "*.DS_Store" "deploy*.sh" "*.zip" "*.log" ".aws-sam"
echo " [OK] Package ZIP creato"

echo " > Upload su S3 $S3_BUCKET..."
aws s3 cp "$APP_NAME.zip" "s3://$S3_BUCKET/$APP_NAME.zip"
echo " [OK] Upload completato"

VERSION_LABEL="v-complete-$(date +%Y%m%d%H%M%S)"

echo " > Creazione versione $VERSION_LABEL"
aws elasticbeanstalk create-application-version \
  --application-name "$APP_NAME" \
  --region "$REGION" \
  --version-label "$VERSION_LABEL" \
  --source-bundle S3Bucket="$S3_BUCKET",S3Key="$APP_NAME.zip"
echo " [OK] Versione applicazione creata"

echo " > Verifica ambiente esistente..."
ENV_INFO=$(aws elasticbeanstalk describe-environments --application-name "$APP_NAME" --environment-names "$ENV_NAME" --region "$REGION" --query 'Environments[0]' --output json 2>/dev/null)
ENV_STATUS=$(echo "$ENV_INFO" | jq -r .Status)
if [[ "$ENV_STATUS" == "Ready" || "$ENV_STATUS" == "Updating" || "$ENVSTATUS" == "Launching" ]]; then
  echo " > Aggiornamento environment esistente $ENV_NAME"
  aws elasticbeanstalk update-environment \
    --application-name "$APP_NAME" \
    --environment-name "$ENV_NAME" \
    --version-label "$VERSION_LABEL" \
    --option-settings Namespace=aws:autoscaling:launchconfiguration,OptionName=IamInstanceProfile,Value=aws-elasticbeanstalk-ec2-role \
    --region "$REGION"
else
  echo " > Creazione nuovo environment $ENV_NAME"
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
    --option-settings Namespace=aws:elasticbeanstalk:environment,OptionName=EnvironmentType,Value=SingleInstance \
                      Namespace=aws:autoscaling:launchconfiguration,OptionName=InstanceType,Value=t3.micro \
                      Namespace=aws:elasticbeanstalk:environment,OptionName=ServiceRole,Value=aws-elasticbeanstalk-service-role \
                      Namespace=aws:autoscaling:launchconfiguration,OptionName=IamInstanceProfile,Value=aws-elasticbeanstalk-ec2-role \
    --region "$REGION"
fi

echo "--------------------------------------------------"
echo "--- MONITORAGGIO DEPLOY ---"
DEPLOY_SUCCESS=false
for ((i=1; i<=MAX_MONITORING_CYCLES; i++)); do
  ENVDATA=$(aws elasticbeanstalk describe-environments --application-name "$APP_NAME" --environment-names "$ENV_NAME" --region "$REGION" --query 'Environments[0]' --output json 2>/dev/null)
  STATUS=$(echo "$ENVDATA" | jq -r .Status)
  HEALTH=$(echo "$ENVDATA" | jq -r .Health)
  echo "Ciclo $i: Stato $STATUS - Salute $HEALTH"
  if [[ "$STATUS" == "Launching" && $i -gt 5 ]]; then
    echo "Eventi recenti:"
    aws elasticbeanstalk describe-events --environment-name "$ENV_NAME" --region "$REGION" --max-items 2 --query 'Events[*].Message' --output text | head -1
    echo "Nessun evento importante"
  fi
  if [[ "$STATUS" == "Ready" && "$HEALTH" == "Green" ]]; then
    EB_URL=$(echo "$ENVDATA" | jq -r .CNAME)
    echo
    echo "=================================================="
    echo " DEPLOY COMPLETATO CON SUCCESSO!"
    echo "=================================="
    echo " URL Applicazione: http://$EB_URL"
    echo " API Gateway: $API_URL"
    echo "--------------------------------------------------"
    echo " Credenziali di test"
    echo " Email: test@filmrecommender.com"
    echo " Password: Password123!"
    echo "--------------------------------------------------"
    DEPLOY_SUCCESS=true
    break
  elif [[ "$STATUS" == "Terminated" || "$STATUS" == "Terminating" ]]; then
    echo " ERRORE: Environment in stato $STATUS"
    echo " Ultimi eventi:"
    aws elasticbeanstalk describe-events --environment-name "$ENV_NAME" --region "$REGION" --max-items 5 --query 'Events[*].Message' --output text
    break
  fi
  sleep $MONITORING_INTERVAL
done

echo "--------------------------------------------------"
if [ "$DEPLOY_SUCCESS" = true ]; then
  echo " SUCCESSO: Il deploy è completo."
  echo " L'applicazione è disponibile all'URL sopra indicato"
  echo " Per aggiornamenti futuri, esegui semplicemente ./deploy.sh"
else
  echo " ERRORE: Deploy non completato o in stato incerto."
  echo " Controlla manualmente con:"
  echo " aws elasticbeanstalk describe-environments --application-name $APP_NAME --environment-names $ENV_NAME --region $REGION"
  echo " aws elasticbeanstalk describe-events --environment-name $ENV_NAME --region $REGION"
fi

echo "=================================================="