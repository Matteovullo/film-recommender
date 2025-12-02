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

# --- CONFIGURAZIONE IAM COMPLETA ---
echo "--------------------------------------------------"
echo "--- CONFIGURAZIONE IAM ROLES (COMPLETA) ---"

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
    echo " > Creazione Instance Profile..."
    aws iam create-instance-profile --instance-profile-name aws-elasticbeanstalk-ec2-role
    sleep 5
    aws iam add-role-to-instance-profile --instance-profile-name aws-elasticbeanstalk-ec2-role --role-name aws-elasticbeanstalk-ec2-role
    echo " [OK] Instance Profile creato e associato"
fi

# --- ATTACCO TUTTE LE POLICY NECESSARIE ALL'EC2 ROLE ---
echo " > Attacco TUTTE le policy necessarie al EC2 Role..."

# 1. Policy standard Elastic Beanstalk
echo "   - Attacco policy Elastic Beanstalk standard..."
aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-ec2-role \
    --policy-arn arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier \
    2>/dev/null || echo "   [INFO] Policy WebTier già attaccata"

aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-ec2-role \
    --policy-arn arn:aws:iam::aws:policy/AWSElasticBeanstalkMulticontainerDocker \
    2>/dev/null || echo "   [INFO] Policy MulticontainerDocker già attaccata"

aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-ec2-role \
    --policy-arn arn:aws:iam::aws:policy/AWSElasticBeanstalkWorkerTier \
    2>/dev/null || echo "   [INFO] Policy WorkerTier già attaccata"

# 2. Policy CRITICHE per risolvere errori EC2 e AutoScaling
echo "   - Attacco policy CRITICHE AmazonEC2FullAccess..."
aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-ec2-role \
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess \
    2>/dev/null || echo "   [INFO] Policy AmazonEC2FullAccess già attaccata"

echo "   - Attacco policy CRITICHE AutoScalingFullAccess..."
aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-ec2-role \
    --policy-arn arn:aws:iam::aws:policy/AutoScalingFullAccess \
    2>/dev/null || echo "   [INFO] Policy AutoScalingFullAccess già attaccata"

# 3. Policy aggiuntive per Amazon Linux 2023
echo "   - Attacco policy CloudWatchLogsFullAccess..."
aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-ec2-role \
    --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess \
    2>/dev/null || echo "   [INFO] Policy CloudWatchLogsFullAccess già attaccata"

# 4. Policy custom con TUTTI i permessi Describe specifici
echo "   - Creazione policy custom EC2-Describe-Completa..."
aws iam put-role-policy \
  --role-name aws-elasticbeanstalk-ec2-role \
  --policy-name eb-ec2-complete-describe-permissions \
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
          "ec2:DescribeInstanceAttribute",
          "ec2:DescribeInstanceCreditSpecifications",
          "ec2:DescribeTags",
          "ec2:DescribeKeyPairs",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeVolumes",
          "ec2:DescribeVolumeStatus",
          "ec2:DescribeVolumeAttribute",
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeRegions"
        ],
        "Resource": "*"
      }
    ]
  }' \
  --region "$REGION" 2>/dev/null || echo "   [INFO] Policy custom già esistente"

echo " > Verifica finale permessi IAM..."
echo "   Ruolo EC2:"
aws iam list-attached-role-policies --role-name aws-elasticbeanstalk-ec2-role --query 'AttachedPolicies[].PolicyArn' --output table 2>/dev/null || echo "   [ERRORE] Impossibile listare policy"

echo " > Attesa propagazione IAM (30 secondi)..."
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

# --- ELASTIC BEANSTALK CONFIG AND DEPLOYMENT ---
echo "--------------------------------------------------"
echo "--- SETUP ELASTIC BEANSTALK ---"

rm -rf .ebextensions
mkdir -p .ebextensions

echo " > Generazione dockerrun.aws.json..."
cat > dockerrun.aws.json <<EOL
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

echo " > Generazione .ebextensions/01-app.config (SEMPLICE E FUNZIONANTE)..."
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

  # Impostazioni IAM CRITICHE
  - namespace: aws:autoscaling:launchconfiguration
    option_name: IamInstanceProfile
    value: aws-elasticbeanstalk-ec2-role
  - namespace: aws:elasticbeanstalk:environment
    option_name: ServiceRole
    value: aws-elasticbeanstalk-service-role
  - namespace: aws:elasticbeanstalk:environment
    option_name: EnvironmentType
    value: SingleInstance
  - namespace: aws:autoscaling:launchconfiguration
    option_name: InstanceType
    value: t3.micro
  - namespace: aws:elasticbeanstalk:environment
    option_name: LoadBalancerType
    value: application
EOL

echo " > Creazione S3 bucket per EB se non esiste..."
if ! aws s3 ls "s3://$S3_BUCKET" --region $REGION &>/dev/null; then
    aws s3 mb "s3://$S3_BUCKET" --region $REGION
    echo " [OK] Bucket S3 creato"
else
    echo " [OK] Bucket S3 già esistente"
fi

echo " > Preparazione package EB..."
rm -f "$APP_NAME.zip"
# Includi SOLO i file necessari, senza funzioni YAML complesse
zip -r "$APP_NAME.zip" dockerrun.aws.json Dockerfile application.py requirements.txt static .ebextensions \
    -x "*.git*" "*.DS_STORE" "deploy*.sh" "*.zip" "*.log" ".aws-sam" "*.bak" "__pycache__/*" "*.pyc"
echo " [OK] Package ZIP creato"

echo " > Upload su S3 $S3_BUCKET..."
aws s3 cp "$APP_NAME.zip" "s3://$S3_BUCKET/$APP_NAME.zip"
echo " [OK] Upload completato"

VERSION_LABEL="v-$(date +%Y%m%d%H%M%S)"

echo " > Creazione versione $VERSION_LABEL"
aws elasticbeanstalk create-application-version \
  --application-name "$APP_NAME" \
  --region "$REGION" \
  --version-label "$VERSION_LABEL" \
  --source-bundle S3Bucket="$S3_BUCKET",S3Key="$APP_NAME.zip"
echo " [OK] Versione applicazione creata"

echo " > Verifica ambiente esistente..."
ENV_INFO=$(aws elasticbeanstalk describe-environments --application-name "$APP_NAME" --environment-names "$ENV_NAME" --region "$REGION" --query 'Environments[0]' --output json 2>/dev/null || echo "{}")
ENV_STATUS=$(echo "$ENV_INFO" | jq -r '.Status // "NOT_EXIST"')
if [[ "$ENV_STATUS" == "Ready" || "$ENV_STATUS" == "Updating" || "$ENV_STATUS" == "Launching" ]]; then
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
  
  echo " > Creazione ambiente Elastic Beanstalk..."
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

echo "--------------------------------------------------"
echo "--- MONITORAGGIO DEPLOY ---"
echo " ⏳ Questo processo potrebbe richiedere 10-15 minuti..."
echo "    Per monitorare manualmente:"
echo "    aws elasticbeanstalk describe-environments --application-name $APP_NAME --environment-names $ENV_NAME --region $REGION"

DEPLOY_SUCCESS=false
for ((i=1; i<=MAX_MONITORING_CYCLES; i++)); do
  ENVDATA=$(aws elasticbeanstalk describe-environments --application-name "$APP_NAME" --environment-names "$ENV_NAME" --region "$REGION" --query 'Environments[0]' --output json 2>/dev/null || echo "{}")
  STATUS=$(echo "$ENVDATA" | jq -r '.Status // "UNKNOWN"')
  HEALTH=$(echo "$ENVDATA" | jq -r '.Health // "Grey"')
  
  echo " Ciclo $i/$MAX_MONITORING_CYCLES - Stato: $STATUS - Salute: $HEALTH"
  
  if [[ "$STATUS" == "Ready" && "$HEALTH" == "Green" ]]; then
    EB_URL=$(echo "$ENVDATA" | jq -r '.CNAME // ""')
    echo
    echo "=================================================="
    echo " ✅ DEPLOY COMPLETATO CON SUCCESSO!"
    echo "=================================================="
    echo " 🌐 URL Applicazione: http://$EB_URL"
    echo " 🔗 API Gateway: $API_URL"
    echo "--------------------------------------------------"
    echo " 📧 Credenziali di test"
    echo "    Email: test@filmrecommender.com"
    echo "    Password: Password123!"
    echo "--------------------------------------------------"
    echo " 🔧 Comandi di verifica:"
    echo "    aws elasticbeanstalk describe-environment-health --environment-name $ENV_NAME --region $REGION"
    echo "    aws elasticbeanstalk describe-events --environment-name $ENV_NAME --region $REGION"
    echo "=================================================="
    DEPLOY_SUCCESS=true
    break
  elif [[ "$STATUS" == "Terminated" || "$STATUS" == "Terminating" ]]; then
    echo " ❌ ERRORE: Environment in stato $STATUS"
    echo " Ultimi eventi:"
    aws elasticbeanstalk describe-events --environment-name "$ENV_NAME" --region "$REGION" --max-items 5 --query 'Events[*].Message' --output text 2>/dev/null || echo "   Nessun evento disponibile"
    break
  fi
  
  # Mostra eventi ogni 5 cicli
  if (( i % 5 == 0 )); then
    echo "   Eventi recenti:"
    aws elasticbeanstalk describe-events --environment-name "$ENV_NAME" --region "$REGION" --max-items 2 --query 'Events[*].Message' --output text 2>/dev/null | head -1 || echo "   Nessun evento importante"
  fi
  
  sleep $MONITORING_INTERVAL
done

# Pulizia file temporanei
rm -f dockerrun.aws.json "$APP_NAME.zip"
rm -rf .ebextensions

echo "=================================================="
if [ "$DEPLOY_SUCCESS" = true ]; then
  echo " 🎉 SUCCESSO: Il deploy è completo!"
  echo "    L'applicazione è disponibile all'URL sopra indicato"
  echo "    Per aggiornamenti futuri, esegui semplicemente questo script"
else
  echo " ⚠️  AVVISO: Deploy non completato o in stato incerto."
  echo "    Controlla manualmente con:"
  echo "    aws elasticbeanstalk describe-environments --application-name $APP_NAME --environment-names $ENV_NAME --region $REGION"
  echo "    aws elasticbeanstalk describe-events --environment-name $ENV_NAME --region $REGION"
  echo ""
  echo " 🔧 TROUBLESHOOTING:"
  echo "    1. Verifica permessi IAM:"
  echo "       aws iam list-attached-role-policies --role-name aws-elasticbeanstalk-ec2-role"
  echo "    2. Controlla errori EC2:"
  echo "       aws ec2 describe-instances --filters \"Name=tag-key,Values=elasticbeanstalk:environment-name\" \"Name=tag-value,Values=$ENV_NAME\" --query 'Reservations[].Instances[].State' --region $REGION"
  echo "    3. Verifica log CloudWatch:"
  echo "       Visita la console CloudWatch nella regione $REGION"
fi

echo "=================================================="