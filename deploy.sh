#!/bin/bash
set -e

ACCOUNTID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
if [ -z "$ACCOUNTID" ]; then
  echo "ERRORE: Impossibile recuperare l'ID Account AWS. Verifica le tue credenziali."
  exit 1
fi

REGION="eu-west-1"
APPNAME="film-recommender-final"
ECRREPO="film-recommender"
S3BUCKET="elasticbeanstalk-$REGION-$ACCOUNTID"
LAMBDASTACK="${APPNAME}-lambda"
ENVNAME="${APPNAME}-env"
SOLUTIONSTACK="64bit Amazon Linux 2023 v4.7.2 running Docker"
MONITORINGINTERVAL=20
MAXMONITORINGCYCLES=60

echo
echo "FILM RECOMMENDER - DEPLOY COMPLETO E DEFINITIVO"
echo "REGIONE: $REGION"
echo "ACCOUNT: $ACCOUNTID"
echo "APPLICAZIONE: $APPNAME"
echo "--------------------------------------------------"

# Check essential files
ESSENTIALFILES=("application.py" "requirements.txt" "Dockerfile" "static/html/index.html" "static/js/auth.js")
for file in "${ESSENTIALFILES[@]}"; do
  if [ ! -f "$file" ]; then
    echo "ERRORE: File mancante $file"
    exit 1
  fi
done
echo "OK: Tutti i file essenziali presenti"

echo "--- DEPLOY SERVIZI SERVERLESS SAM ---"
if command -v sam >/dev/null; then
  echo "Building SAM application..."
  sam build
  echo "Deploying Lambda stack $LAMBDASTACK..."
  sam deploy --stack-name "$LAMBDASTACK" --capabilities CAPABILITY_IAM --region "$REGION" --resolve-s3 --no-confirm-changeset --no-fail-on-empty-changeset
  APIURL=$(aws cloudformation describe-stacks --stack-name "$LAMBDASTACK" --region "$REGION" --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' --output text 2>/dev/null)
  if [ -n "$APIURL" ]; then
    echo "OK: API Gateway URL $APIURL"
    # Aggiornamento URL API nei file JavaScript
    sed -i.bak "s|let APIBASEURL = .*|let APIBASEURL = '$APIURL';|g" static/js/app.js 2>/dev/null || true
    find static/js -name "*.bak" -delete 2>/dev/null || true
  else
    echo "ATTENZIONE: API Gateway URL non disponibile. Uso il placeholder."
    APIURL="https://g1q9d4xdfg.execute-api.eu-west-1.amazonaws.com/Prod"
  fi
else
  echo "ATTENZIONE: SAM CLI non installato - salto deploy Lambda"
  APIURL="https://g1q9d4xdfg.execute-api.eu-west-1.amazonaws.com/Prod"
fi

echo "--------------------------------------------------"
echo "--- CONFIGURAZIONE IAM ROLES ---"

# --- Correzione ruolo EC2 e instance profile ---
if ! aws iam get-role --role-name aws-elasticbeanstalk-ec2-role --region "$REGION" >/dev/null 2>&1; then
  echo "Creazione EC2 Role..."
  aws iam create-role \
    --role-name aws-elasticbeanstalk-ec2-role \
    --assume-role-policy-document '{
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "ec2.amazonaws.com"},
        "Action": "sts:AssumeRole"
      }]
    }' \
    --description "Elastic Beanstalk EC2 Role" \
    --region "$REGION"
  echo "OK EC2 Role creato"
fi

if ! aws iam get-instance-profile --instance-profile-name aws-elasticbeanstalk-ec2-role --region "$REGION" >/dev/null 2>&1; then
  aws iam create-instance-profile --instance-profile-name aws-elasticbeanstalk-ec2-role --region "$REGION"
  sleep 5
  aws iam add-role-to-instance-profile --instance-profile-name aws-elasticbeanstalk-ec2-role --role-name aws-elasticbeanstalk-ec2-role --region "$REGION"
  echo "OK Instance Profile creato e associato"
fi

# Policy gestite standard
aws iam attach-role-policy \
  --role-name aws-elasticbeanstalk-ec2-role \
  --policy-arn arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier \
  --region "$REGION"

aws iam attach-role-policy \
  --role-name aws-elasticbeanstalk-ec2-role \
  --policy-arn arn:aws:iam::aws:policy/AWSElasticBeanstalkMulticontainerDocker \
  --region "$REGION"

aws iam attach-role-policy \
  --role-name aws-elasticbeanstalk-ec2-role \
  --policy-arn arn:aws:iam::aws:policy/AWSElasticBeanstalkWorkerTier \
  --region "$REGION"

# Policy custom EC2 richieste
aws iam put-role-policy \
  --role-name aws-elasticbeanstalk-ec2-role \
  --policy-name custom-eb-ec2-permissions \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeLaunchTemplates",
        "ec2:DescribeImages"
      ],
      "Resource": "*"
    }]
  }' \
  --region "$REGION"

echo "Attesa propagazione IAM 30s..."
sleep 30

echo "--------------------------------------------------"
echo "--- SETUP ECR E DOCKER ---"
if ! aws ecr describe-repositories --repository-names "$ECRREPO" --region "$REGION" >/dev/null 2>&1; then
  echo "Creazione repository ECR $ECRREPO"
  aws ecr create-repository --repository-name "$ECRREPO" --region "$REGION"
  echo "OK Repository ECR creato"
else
  echo "OK Repository ECR già esistente"
fi
ECRURL=$(aws ecr describe-repositories --repository-names "$ECRREPO" --region "$REGION" --query 'repositories[0].repositoryUri' --output text)
echo "ECR Repository URI: $ECRURL"
echo "Login a ECR..."
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ECRURL"
echo "OK Login Succeeded"
echo "Build e push immagine Docker..."
docker build -t "$ECRREPO" .
docker tag "$ECRREPO:latest" "$ECRURL:latest"
docker push "$ECRURL:latest"
echo "OK Immagine Docker pushata su ECR"
echo "Pulizia Docker locale..."
docker container prune -f || true
docker image prune -a -f || true
echo "OK Pulizia Docker completata"

echo "--------------------------------------------------"
echo "--- SETUP ELASTIC BEANSTALK ---"
rm -rf .ebextensions
mkdir -p .ebextensions
echo "Generazione dockerrun.aws.json..."
cat > dockerrun.aws.json <<EOL
{
  "AWSEBDockerrunVersion": 1,
  "Image": {
    "Name": "$ECRURL:latest",
    "Update": true
  },
  "Ports": [
    {
      "ContainerPort": 8000
    }
  ]
}
EOL

echo "Generazione .ebextensions/01-app.config (Correzione Static Files)..."
cat > .ebextensions/01-app.config <<EOL
option_settings:
  - namespace: aws:elasticbeanstalk:application:environment
    option_name: AWS_REGION
    value: $REGION
  - namespace: aws:elasticbeanstalk:application:environment
    option_name: FLASK_ENV
    value: production
  - namespace: aws:elasticbeanstalk:application:environment
    option_name: APIGATEWAY_URL
    value: $APIURL
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

echo "Creazione/verifica applicazione EB..."
aws elasticbeanstalk create-application --application-name "$APPNAME" --region "$REGION" 2>/dev/null || echo "OK Applicazione EB già esistente"
sleep 5
echo "Preparazione package EB..."
rm -f "$APPNAME.zip"
zip -r "$APPNAME.zip" dockerrun.aws.json Dockerfile application.py requirements.txt static .ebextensions -x "*.git*" "*.DS_Store" "deploy*.sh" "*.zip" "*.log" ".aws-sam"
echo "OK Package ZIP creato"

echo "Upload su S3 $S3BUCKET..."
aws s3 cp "$APPNAME.zip" "s3://$S3BUCKET/$APPNAME.zip"
echo "OK Upload completato"

VERSIONLABEL="v-complete-$(date +%Y%m%d%H%M%S)"

echo "Creazione versione $VERSIONLABEL"
aws elasticbeanstalk create-application-version \
  --application-name "$APPNAME" \
  --region "$REGION" \
  --version-label "$VERSIONLABEL" \
  --source-bundle S3Bucket="$S3BUCKET",S3Key="$APPNAME.zip"
echo "OK Versione applicazione creata"

echo "Verifica ambiente esistente..."
ENVINFO=$(aws elasticbeanstalk describe-environments --application-name "$APPNAME" --environment-names "$ENVNAME" --region "$REGION" --query 'Environments[0]' --output json 2>/dev/null)
ENVSTATUS=$(echo "$ENVINFO" | jq -r .Status)
if [[ "$ENVSTATUS" == "Ready" || "$ENVSTATUS" == "Updating" || "$ENVSTATUS" == "Launching" ]]; then
  echo "Aggiornamento environment esistente $ENVNAME"
  aws elasticbeanstalk update-environment \
    --application-name "$APPNAME" \
    --environment-name "$ENVNAME" \
    --version-label "$VERSIONLABEL" \
    --option-settings Namespace=aws:autoscaling:launchconfiguration,OptionName=IamInstanceProfile,Value=aws-elasticbeanstalk-ec2-role \
    --region "$REGION"
else
  echo "Creazione nuovo environment $ENVNAME"
  if [[ "$ENVSTATUS" == "Terminated" ]]; then
    echo "Pulizia ambiente terminato..."
    aws elasticbeanstalk delete-environment --environment-name "$ENVNAME" --region "$REGION" 2>/dev/null || true
    sleep 10
  fi
  aws elasticbeanstalk create-environment \
    --application-name "$APPNAME" \
    --environment-name "$ENVNAME" \
    --solution-stack-name "$SOLUTIONSTACK" \
    --version-label "$VERSIONLABEL" \
    --option-settings Namespace=aws:elasticbeanstalk:environment,OptionName=EnvironmentType,Value=SingleInstance \
                      Namespace=aws:autoscaling:launchconfiguration,OptionName=InstanceType,Value=t3.micro \
                      Namespace=aws:elasticbeanstalk:environment,OptionName=ServiceRole,Value=aws-elasticbeanstalk-service-role \
                      Namespace=aws:autoscaling:launchconfiguration,OptionName=IamInstanceProfile,Value=aws-elasticbeanstalk-ec2-role \
    --region "$REGION"
fi

echo "--------------------------------------------------"
echo "--- MONITORAGGIO DEPLOY ---"
DEPLOYSUCCESS=false
for ((i=1; i<=MAXMONITORINGCYCLES; i++)); do
  ENVDATA=$(aws elasticbeanstalk describe-environments --application-name "$APPNAME" --environment-names "$ENVNAME" --region "$REGION" --query 'Environments[0]' --output json 2>/dev/null)
  STATUS=$(echo "$ENVDATA" | jq -r .Status)
  HEALTH=$(echo "$ENVDATA" | jq -r .Health)
  echo "Ciclo $i: Stato $STATUS - Salute $HEALTH"
  if [[ "$STATUS" == "Launching" && $i -gt 5 ]]; then
    echo "Eventi recenti:"
    aws elasticbeanstalk describe-events --environment-name "$ENVNAME" --region "$REGION" --max-items 2 --query 'Events[*].Message' --output text | head -1
    echo "Nessun evento importante"
  fi
  if [[ "$STATUS" == "Ready" && "$HEALTH" == "Green" ]]; then
    EBURL=$(echo "$ENVDATA" | jq -r .CNAME)
    echo
    echo "DEPLOY COMPLETATO CON SUCCESSO!"
    echo "URL Applicazione: http://$EBURL"
    echo "API Gateway: $APIURL"
    echo "--------------------------------------------------"
    echo "Credenziali di test"
    echo "Email: test@filmrecommender.com"
    echo "Password: Password123!"
    echo "--------------------------------------------------"
    DEPLOYSUCCESS=true
    break
  elif [[ "$STATUS" == "Terminated" || "$STATUS" == "Terminating" ]]; then
    echo "ERRORE: Environment in stato $STATUS"
    echo "Ultimi eventi:"
    aws elasticbeanstalk describe-events --environment-name "$ENVNAME" --region "$REGION" --max-items 5 --query 'Events[*].Message' --output text
    break
  fi
  sleep $MONITORINGINTERVAL
done
echo "--------------------------------------------------"
if [ "$DEPLOYSUCCESS" = true ]; then
  echo "SUCCESSO: Il deploy è completo. L'applicazione è disponibile all'URL sopra indicato."
  echo "Per aggiornamenti futuri, esegui semplicemente ./deploy.sh"
else
  echo "ERRORE: Deploy non completato o in stato incerto."
  echo "Controlla manualmente con:"
  echo "aws elasticbeanstalk describe-environments --application-name $APPNAME --environment-names $ENVNAME --region $REGION"
  echo "aws elasticbeanstalk describe-events --environment-name $ENVNAME --region $REGION"
fi
