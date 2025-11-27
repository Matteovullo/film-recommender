#!/bin/bash
set -e

REGION="eu-west-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO="film-recommender"

echo "=================================================="
echo " 🐳 SETUP ECR E DOCKER"
echo "=================================================="

# 1. CREA REPOSITORY ECR
echo "1. Creazione repository ECR..."
if ! aws ecr describe-repositories --repository-names $ECR_REPO --region $REGION &>/dev/null; then
    aws ecr create-repository --repository-name $ECR_REPO --region $REGION
    echo " ✅ Repository ECR creato"
else
    echo " ✅ Repository ECR già esistente"
fi

ECR_URL=$(aws ecr describe-repositories --repository-names $ECR_REPO --region $REGION --query 'repositories[0].repositoryUri' --output text)
echo " ECR URL: $ECR_URL"

# 2. LOGIN ECR
echo "2. Login a ECR..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_URL
echo " ✅ Login ECR riuscito"

# 3. BUILD E PUSH DOCKER
echo "3. Build e push immagine Docker..."
docker build -t $ECR_REPO .
docker tag $ECR_REPO:latest $ECR_URL:latest
docker push $ECR_URL:latest
echo " ✅ Immagine Docker pushata su ECR"

# 4. PULIZIA DOCKER LOCALE
echo "4. Pulizia Docker locale..."
docker container prune -f 2>/dev/null || true
docker image prune -a -f 2>/dev/null || true
echo " ✅ Pulizia completata"

echo "=================================================="
echo " ✅ ECR E DOCKER SETUP COMPLETATO"
echo "=================================================="
echo "Repository: $ECR_URL"
echo "Immagine: $ECR_URL:latest"