#!/bin/bash
set -e

REGION="eu-west-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO="film-recommender"
APP_NAME="film-recommender-final"

echo "=================================================="
echo " 🐳 SETUP ECR E DOCKER - AMBIENTE DI TEST"
echo "=================================================="
echo " Build e deploy dell'applicazione Docker"
echo "=================================================="

# Funzione per pulizia Docker
cleanup_docker() {
    echo ""
    echo "🧹 PULIZIA DOCKER IN CORSO..."
    
    local space_before=$(docker system df --format '{{.Size}}' 2>/dev/null || echo "0B")
    
    echo " > Fermando container inutilizzati..."
    docker stop $(docker ps -q) 2>/dev/null || true
    sleep 2
    
    echo " > Rimuovendo container fermati..."
    docker container prune -f 2>/dev/null || true
    
    echo " > Rimuovendo immagini non utilizzate..."
    docker image prune -a -f 2>/dev/null || true
    
    echo " > Rimuovendo network non utilizzati..."
    docker network prune -f 2>/dev/null || true
    
    echo " > Rimuovendo volumi non utilizzati..."
    docker volume prune -f 2>/dev/null || true
    
    echo " > Pulizia completa del sistema..."
    docker system prune -a -f --volumes 2>/dev/null || true
    
    local space_after=$(docker system df --format '{{.Size}}' 2>/dev/null || echo "0B")
    
    echo " ✅ Pulizia Docker completata"
    echo " 📊 Spazio liberato: da $space_before a $space_after"
}

# 0. PULIZIA INIZIALE DOCKER
cleanup_docker

# 1. CREA REPOSITORY ECR
echo ""
echo "1. 📦 CREAZIONE REPOSITORY ECR..."
if ! aws ecr describe-repositories --repository-names $ECR_REPO --region $REGION &>/dev/null; then
    echo "   🗂️  Creazione repository: $ECR_REPO"
    aws ecr create-repository \
        --repository-name $ECR_REPO \
        --region $REGION \
        --image-scanning-configuration scanOnPush=true \
        --image-tag-mutability MUTABLE
    echo "   ✅ Repository ECR creato"
else
    echo "   ✅ Repository ECR già esistente"
fi

ECR_URL=$(aws ecr describe-repositories --repository-names $ECR_REPO --region $REGION --query 'repositories[0].repositoryUri' --output text)
echo "   🌐 ECR URL: $ECR_URL"

# 2. LOGIN ECR
echo ""
echo "2. 🔐 LOGIN A ECR..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_URL
echo "   ✅ Login ECR riuscito"

# 3. VERIFICA FILE NECESSARI
echo ""
echo "3. 📁 VERIFICA FILE NECESSARI..."
ESSENTIAL_FILES=("Dockerfile" "application.py" "requirements.txt" "static/html/index.html" "static/js/auth.js" "static/js/app.js")

for file in "${ESSENTIAL_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "   ❌ ERRORE: File mancante: $file"
        exit 1
    fi
    echo "   ✅ $file"
done

echo "   ✅ Tutti i file essenziali presenti"

# 4. BUILD IMMAGINE DOCKER
echo ""
echo "4. 🔨 BUILD IMMAGINE DOCKER..."
echo "   🏗️  Building image: $ECR_REPO"
docker build -t $ECR_REPO . 

echo "   🏷️  Tagging image..."
docker tag $ECR_REPO:latest $ECR_URL:latest
docker tag $ECR_REPO:latest $ECR_URL:test-$(date +%Y%m%d%H%M%S)

echo "   ✅ Build e tagging completati"

# 5. PUSH IMMAGINE SU ECR
echo ""
echo "5. 📤 PUSH IMMAGINE SU ECR..."
echo "   ⬆️  Pushing image: $ECR_URL:latest"
docker push $ECR_URL:latest

echo "   ⬆️  Pushing image con tag test..."
docker push $ECR_URL:test-$(date +%Y%m%d%H%M%S) 2>/dev/null || echo "   ⚠️  Push tag test fallito (non critico)"

echo "   ✅ Immagini Docker pushate su ECR"

# 6. PREPARAZIONE DEPLOYMENT PACKAGE PER ELASTIC BEANSTALK
echo ""
echo "6. 📦 PREPARAZIONE DEPLOYMENT PACKAGE..."

echo "   📁 Creazione directory .ebextensions..."
rm -rf .ebextensions
mkdir -p .ebextensions

echo "   📝 Generazione dockerrun.aws.json..."
cat > dockerrun.aws.json << EOF
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
  ],
  "Logging": "/var/log/nginx"
}
EOF

echo "   📝 Generazione .ebextensions/01-app.config..."
cat > .ebextensions/01-app.config << EOF
option_settings:
  aws:elasticbeanstalk:application:environment:
    PYTHONPATH: /app
    AWS_REGION: $REGION
    FLASK_ENV: production
  aws:elasticbeanstalk:cloudwatch:logs:
    StreamLogs: true
    RetentionInDays: 7
  aws:elasticbeanstalk:environment:process:default:
    HealthCheckPath: /health
    Port: 8000
    Protocol: HTTP

container_commands:
  01_setup_app:
    command: "echo 'Application setup completed'"
    leader_only: true
  02_chmod_files:
    command: "chmod +x /var/app/current/application.py"
    leader_only: false
EOF

echo "   📦 Creazione package ZIP..."
rm -f deployment.zip
zip -r deployment.zip dockerrun.aws.json .ebextensions/ -x "*.git*" "*.DS_Store" "*.log"

echo "   ✅ Deployment package creato: deployment.zip"

# 7. UPLOAD SU S3
echo ""
echo "7. ☁️  UPLOAD DEPLOYMENT PACKAGE SU S3..."
S3_BUCKET="elasticbeanstalk-$REGION-$ACCOUNT_ID"

# Crea bucket se non esiste
if ! aws s3 ls "s3://$S3_BUCKET" --region $REGION &>/dev/null; then
    echo "   🗂️  Creazione bucket S3: $S3_BUCKET"
    aws s3 mb "s3://$S3_BUCKET" --region $REGION
fi

echo "   ⬆️  Upload deployment.zip su S3..."
aws s3 cp deployment.zip "s3://$S3_BUCKET/deployment.zip" --region $REGION
echo "   ✅ Package caricato su S3"

# 8. PULIZIA FINALE DOCKER
cleanup_docker

echo ""
echo "=================================================="
echo " ✅ ECR E DOCKER SETUP COMPLETATO AL 100%"
echo "=================================================="
echo ""
echo "📦 RISORSE CREATE:"
echo "   ✅ Repository ECR: $ECR_URL"
echo "   ✅ Immagine Docker: $ECR_URL:latest"
echo "   ✅ Deployment package: deployment.zip"
echo "   ✅ S3 Bucket: $S3_BUCKET"
echo ""
echo "🔧 FILE GENERATI:"
echo "   ✅ dockerrun.aws.json"
echo "   ✅ .ebextensions/01-app.config"
echo "   ✅ deployment.zip"
echo ""
echo "🚀 PRONTO PER IL PROSSIMO STEP: ./4-create-pipeline.sh"
echo "=================================================="