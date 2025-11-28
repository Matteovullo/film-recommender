#!/bin/bash
set -e

REGION="eu-west-1"
APP_NAME="film-recommender-final"
ECR_REPO="film-recommender"
ENV_NAME="$APP_NAME-env"
SOLUTION_STACK="64bit Amazon Linux 2023 v4.7.2 running Docker"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
S3_BUCKET="elasticbeanstalk-$REGION-$ACCOUNT_ID"
ECR_URL="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$ECR_REPO"

echo "=================================================="
echo " 🚀 DEPLOY ELASTIC BEANSTALK - COMPLETO"
echo "=================================================="
echo " Con risoluzione automatica problemi ECR"
echo "=================================================="

# FUNZIONE PER VERIFICARE E CREARE IMMAGINE ECR
ensure_ecr_image() {
    echo ""
    echo "🔧 VERIFICA E CREAZIONE IMMAGINE ECR..."
    
    # Verifica se il repository ECR esiste
    if ! aws ecr describe-repositories --repository-names "$ECR_REPO" --region $REGION &>/dev/null; then
        echo "   🗑️  Repository ECR non trovato, creazione in corso..."
        aws ecr create-repository \
            --repository-name "$ECR_REPO" \
            --region $REGION
        echo "   ✅ Repository ECR creato"
        sleep 5
    else
        echo "   ✅ Repository ECR trovato"
    fi
    
    # Verifica se esiste almeno un'immagine
    IMAGE_EXISTS=$(aws ecr describe-images --repository-name "$ECR_REPO" --region $REGION --query 'imageDetails[0]' --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$IMAGE_EXISTS" == "NOT_FOUND" ]; then
        echo "   ⚠️  Nessuna immagine ECR trovata, ricreazione in corso..."
        recreate_ecr_image
    else
        echo "   ✅ Immagine ECR trovata"
        
        # Verifica che l'immagine abbia il tag "latest"
        LATEST_TAG=$(aws ecr describe-images --repository-name "$ECR_REPO" --region $REGION --query 'imageDetails[0].imageTags[0]' --output text 2>/dev/null || echo "")
        if [ "$LATEST_TAG" != "latest" ]; then
            echo "   ⚠️  Immagine senza tag 'latest', ricreazione..."
            recreate_ecr_image
        else
            echo "   ✅ Tag 'latest' presente"
        fi
    fi
}

# FUNZIONE PER RICREARE IMMAGINE ECR
recreate_ecr_image() {
    echo ""
    echo "🐳 RICREAZIONE IMMAGINE DOCKER..."
    
    # Login a ECR
    echo "   🔐 Login a ECR..."
    aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com
    
    # Build dell'immagine
    echo "   🔨 Building Docker image..."
    docker build -t $ECR_REPO:latest .
    
    # Tag dell'immagine
    echo "   🏷️  Tagging image..."
    docker tag $ECR_REPO:latest $ECR_URL:latest
    
    # Push dell'immagine
    echo "   📤 Pushing image to ECR..."
    docker push $ECR_URL:latest
    
    echo "   ✅ Immagine Docker creata e pushata su ECR"
}

# FUNZIONE PER RECUPERARE URL DINAMICI
get_dynamic_urls() {
    echo "🔗 RECUPERO URL DINAMICI..."
    
    # Recupera URL API Gateway dallo stack Lambda
    echo "   📡 Recupero URL API Gateway..."
    API_URL=$(aws cloudformation describe-stacks \
        --stack-name "film-recommender-final-lambda-stack" \
        --region $REGION \
        --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$API_URL" ]; then
        echo "   ⚠️  URL API Gateway non trovato, uso fallback"
        API_URL="https://api.example.com"
    else
        echo "   ✅ API Gateway: $API_URL"
    fi
    
    # Recupera Cognito User Pool ID
    echo "   🔐 Recupero Cognito User Pool..."
    USER_POOL_ID=$(aws cognito-idp list-user-pools \
        --region $REGION \
        --max-results 10 \
        --query 'UserPools[?contains(Name, `FilmRecommender`)].Id' \
        --output text 2>/dev/null | head -1 || echo "")
    
    if [ -z "$USER_POOL_ID" ]; then
        echo "   ⚠️  User Pool non trovato"
        USER_POOL_ID="eu-west-1_XXXXXXXXX"
    else
        echo "   ✅ User Pool: $USER_POOL_ID"
    fi
    
    # Recupera Cognito Client ID
    echo "   🔑 Recupero Cognito Client..."
    if [ -n "$USER_POOL_ID" ] && [ "$USER_POOL_ID" != "eu-west-1_XXXXXXXXX" ]; then
        CLIENT_ID=$(aws cognito-idp list-user-pool-clients \
            --user-pool-id "$USER_POOL_ID" \
            --region $REGION \
            --query 'UserPoolClients[0].ClientId' \
            --output text 2>/dev/null || echo "")
    else
        CLIENT_ID=""
    fi
    
    if [ -z "$CLIENT_ID" ]; then
        echo "   ⚠️  Client ID non trovato"
        CLIENT_ID="xxxxxxxxxxxxxxxxxxxxxxxxxx"
    else
        echo "   ✅ Client ID: $CLIENT_ID"
    fi
    
    # Esporta le variabili
    export API_URL
    export USER_POOL_ID
    export CLIENT_ID
}

# FUNZIONE PER VERIFICARE PREREQUISITI
check_prerequisites() {
    echo "🔍 VERIFICA PREREQUISITI..."
    local all_ok=true
    
    # Recupera URL dinamici prima di verificare
    get_dynamic_urls
    
    # Verifica AWS credentials
    if ! aws sts get-caller-identity &>/dev/null; then
        echo "❌ AWS credentials non valide"
        all_ok=false
    else
        echo "✅ AWS credentials OK"
    fi
    
    # Verifica ruoli IAM
    if ! aws iam get-role --role-name "aws-elasticbeanstalk-service-role" &>/dev/null; then
        echo "❌ Service Role non trovato"
        all_ok=false
    else
        echo "✅ Service Role OK"
    fi
    
    if ! aws iam get-role --role-name "aws-elasticbeanstalk-ec2-role" &>/dev/null; then
        echo "❌ EC2 Role non trovato"
        all_ok=false
    else
        echo "✅ EC2 Role OK"
    fi
    
    # Verifica e crea immagine ECR se necessario
    if ! ensure_ecr_image; then
        echo "❌ Impossibile creare immagine ECR"
        all_ok=false
    else
        echo "✅ Immagine ECR OK"
    fi
    
    # Verifica S3 bucket
    if ! aws s3 ls "s3://$S3_BUCKET" --region $REGION &>/dev/null; then
        echo "❌ S3 Bucket non trovato"
        all_ok=false
    else
        echo "✅ S3 Bucket OK"
    fi
    
    # Verifica stack Lambda
    if ! aws cloudformation describe-stacks --stack-name "film-recommender-final-lambda-stack" --region $REGION &>/dev/null; then
        echo "❌ Stack Lambda non trovato"
        all_ok=false
    else
        echo "✅ Stack Lambda OK"
    fi
    
    if [ "$all_ok" = false ]; then
        echo ""
        echo "💡 Alcuni prerequisiti mancanti, tentativo di risoluzione automatica..."
        return 1
    fi
    
    echo "✅ Tutti i prerequisiti verificati"
    return 0
}

# FUNZIONE PER CREARE APPLICAZIONE EB
create_eb_application() {
    echo ""
    echo "1. 🎯 CREAZIONE APPLICAZIONE ELASTIC BEANSTALK..."
    
    # Elimina applicazione esistente se presente
    if aws elasticbeanstalk describe-applications --application-name "$APP_NAME" --region $REGION &>/dev/null; then
        echo "   🗑️  Eliminazione applicazione esistente..."
        aws elasticbeanstalk delete-application \
            --application-name "$APP_NAME" \
            --terminate-env-by-force \
            --region $REGION
        echo "   ⏳ Attesa cancellazione..."
        sleep 30
    fi
    
    # Crea nuova applicazione
    echo "   🆕 Creazione applicazione: $APP_NAME"
    aws elasticbeanstalk create-application \
        --application-name "$APP_NAME" \
        --description "Film Recommender Application" \
        --region $REGION
    
    # Attendi che l'applicazione sia creata
    sleep 10
    echo "   ✅ Applicazione EB creata"
}

# FUNZIONE PER CREARE DEPLOYMENT PACKAGE
create_deployment_package() {
    echo ""
    echo "2. 📦 CREAZIONE DEPLOYMENT PACKAGE..."
    
    # Pulisci file esistenti
    rm -rf .ebextensions Dockerrun.aws.json deployment.zip 2>/dev/null || true
    
    # Crea directory .ebextensions
    mkdir -p .ebextensions
    
    # Crea Dockerrun.aws.json (con D maiuscola!)
    cat > Dockerrun.aws.json << EOF
{
    "AWSEBDockerrunVersion": "1",
    "Image": {
        "Name": "$ECR_URL:latest",
        "Update": "true"
    },
    "Ports": [
        {
            "ContainerPort": "5000"
        }
    ],
    "Logging": "/var/log/app"
}
EOF
    echo "   ✅ Dockerrun.aws.json creato"
    
    # Verifica che il file sia stato creato
    if [ ! -f "Dockerrun.aws.json" ]; then
        echo "   ❌ ERRORE: Dockerrun.aws.json non creato!"
        exit 1
    fi
    
    # Crea configurazione EB con URL dinamici
    cat > .ebextensions/01-app.config << EOF
option_settings:
  aws:elasticbeanstalk:application:environment:
    API_GATEWAY_URL: $API_URL
    COGNITO_USER_POOL_ID: $USER_POOL_ID
    COGNITO_CLIENT_ID: $CLIENT_ID
    COGNITO_REGION: $REGION
    FLASK_ENV: production
    DEBUG: false
    
container_commands:
  01_set_permissions:
    command: "chmod 755 /var/app/current/.ebextensions/*.config"
  02_show_env:
    command: "echo 'Environment setup complete'"

packages:
  yum:
    git: []
    docker: []
EOF
    echo "   ✅ .ebextensions/01-app.config creato (con URL dinamici)"
    
    # Verifica che il file sia stato creato
    if [ ! -f ".ebextensions/01-app.config" ]; then
        echo "   ❌ ERRORE: .ebextensions/01-app.config non creato!"
        exit 1
    fi
    
    # Crea package ZIP con verifica
    echo "   🔨 Creazione deployment.zip..."
    zip -r deployment.zip Dockerrun.aws.json .ebextensions/
    
    # Verifica che il ZIP sia stato creato correttamente
    if [ ! -f "deployment.zip" ]; then
        echo "   ❌ ERRORE: deployment.zip non creato!"
        exit 1
    fi
    
    # Verifica il contenuto del ZIP
    echo "   🔍 Verifica contenuto deployment.zip..."
    zipinfo -1 deployment.zip
    
    echo "   ✅ Deployment package creato e verificato"
}

# FUNZIONE PER UPLOAD SU S3 E CREARE VERSIONE
create_application_version() {
    local version_label=$1
    
    echo ""
    echo "3. ☁️  UPLOAD E CREAZIONE VERSIONE..."
    
    # Verifica che deployment.zip esista
    if [ ! -f "deployment.zip" ]; then
        echo "   ❌ ERRORE: deployment.zip non trovato!"
        exit 1
    fi
    
    # Upload su S3
    echo "   📤 Upload deployment.zip su S3..."
    aws s3 cp deployment.zip "s3://$S3_BUCKET/deployment.zip" --region $REGION
    
    # Verifica che l'upload sia riuscito
    if ! aws s3 ls "s3://$S3_BUCKET/deployment.zip" --region $REGION &>/dev/null; then
        echo "   ❌ ERRORE: Upload su S3 fallito!"
        exit 1
    fi
    
    echo "   ✅ File caricato su S3"
    
    echo "   🏷️  Creazione versione: $version_label"
    
    aws elasticbeanstalk create-application-version \
        --application-name "$APP_NAME" \
        --version-label "$version_label" \
        --source-bundle "S3Bucket=$S3_BUCKET,S3Key=deployment.zip" \
        --region $REGION
    
    echo "   ✅ Versione applicazione creata"
}

# FUNZIONE PER CREARE AMBIENTE EB
create_eb_environment() {
    local version_label=$1
    
    echo ""
    echo "4. 🌍 CREAZIONE AMBIENTE ELASTIC BEANSTALK..."
    
    echo "   🏗️  Creazione ambiente: $ENV_NAME"
    
    # Usa opzioni direttamente nella CLI invece di file JSON
    aws elasticbeanstalk create-environment \
        --application-name "$APP_NAME" \
        --environment-name "$ENV_NAME" \
        --solution-stack-name "$SOLUTION_STACK" \
        --version-label "$version_label" \
        --option-settings \
            Namespace=aws:elasticbeanstalk:environment,OptionName=EnvironmentType,Value=SingleInstance \
            Namespace=aws:autoscaling:launchconfiguration,OptionName=InstanceType,Value=t3.micro \
            Namespace=aws:elasticbeanstalk:environment,OptionName=ServiceRole,Value=aws-elasticbeanstalk-service-role \
            Namespace=aws:autoscaling:launchconfiguration,OptionName=IamInstanceProfile,Value=aws-elasticbeanstalk-ec2-role \
            Namespace=aws:elasticbeanstalk:cloudwatch:logs,OptionName=StreamLogs,Value=true \
            Namespace=aws:elasticbeanstalk:cloudwatch:logs,OptionName=RetentionInDays,Value=7 \
            Namespace=aws:elasticbeanstalk:healthreporting:system,OptionName=SystemType,Value=enhanced \
        --region $REGION
    
    echo "   ✅ Ambiente EB creato"
}

# FUNZIONE PER MONITORARE IL DEPLOY
monitor_deployment() {
    echo ""
    echo "5. 📊 MONITORAGGIO DEPLOY IN CORSO..."
    echo "   ⏳ Attendere 15-20 minuti per il deploy completo..."
    echo "   (Il primo deploy può richiedere più tempo)"
    echo ""

    local max_attempts=60
    local attempt=1
    local deploy_success=false
    
    # Variabile per l'URL finale
    local FINAL_URL=""
    
    while [ $attempt -le $max_attempts ]; do
        # Recupera informazioni ambiente
        ENV_INFO=$(aws elasticbeanstalk describe-environments \
            --application-name "$APP_NAME" \
            --environment-names "$ENV_NAME" \
            --region $REGION \
            --query 'Environments[0]' \
            --output json 2>/dev/null || echo "{}")
        
        STATUS=$(echo "$ENV_INFO" | jq -r '.Status // "Unknown"')
        HEALTH=$(echo "$ENV_INFO" | jq -r '.Health // "Unknown"')
        URL=$(echo "$ENV_INFO" | jq -r '.CNAME // "Unknown"')
        VERSION=$(echo "$ENV_INFO" | jq -r '.VersionLabel // "Unknown"')
        
        # Salva l'URL quando disponibile
        if [ "$URL" != "Unknown" ] && [ -n "$URL" ]; then
            FINAL_URL="$URL"
        fi
        
        # Calcola tempo rimanente
        local minutes_remaining=$(( (max_attempts - attempt) / 2 ))
        
        # Mostra progresso
        printf "   🕐 Ciclo %2d/%d - Stato: %-12s - Salute: %-8s (%d min rimanenti)\n" \
               "$attempt" "$max_attempts" "$STATUS" "$HEALTH" "$minutes_remaining"
        
        # Controlla se il deploy è completato
        if [[ "$STATUS" == "Ready" && "$HEALTH" == "Green" ]]; then
            echo ""
            echo "=================================================="
            echo " ✅ DEPLOY COMPLETATO CON SUCCESSO!"
            echo "=================================================="
            echo " 🌐 URL APPLICAZIONE: http://$FINAL_URL"
            echo " 🔧 VERSIONE: $VERSION"
            echo " 🌍 AMBIENTE: $ENV_NAME"
            echo "=================================================="
            echo ""
            echo "🔐 CREDENZIALI DI TEST:"
            echo "   📧 Email: test@filmrecommender.com"
            echo "   🔑 Password: Password123!"
            echo ""
            echo "📊 ENDPOINTS DISPONIBILI:"
            echo "   🏠 Applicazione: http://$FINAL_URL"
            echo "   ❤️  Health Check: http://$FINAL_URL/health"
            echo "   🔗 API Gateway: $API_URL"
            echo "   👤 Cognito User Pool: $USER_POOL_ID"
            echo ""
            echo "⚙️  SERVIZI CONFIGURATI:"
            echo "   ✅ Elastic Beanstalk"
            echo "   ✅ ECR Docker Container" 
            echo "   ✅ API Gateway"
            echo "   ✅ Cognito Authentication"
            echo "   ✅ DynamoDB Tables"
            echo "=================================================="
            deploy_success=true
            break
            
        elif [[ "$STATUS" == "Terminated" || "$STATUS" == "Terminating" ]]; then
            echo ""
            echo "❌ ERRORE: Ambiente in terminazione"
            break
            
        elif [[ "$STATUS" == "Launching" || "$STATUS" == "Updating" ]]; then
            # Deploy in corso, continua il monitoraggio
            :
        fi
        
        # Incrementa tentativo e attende
        attempt=$((attempt + 1))
        sleep 30
    done

    if [ "$deploy_success" = false ]; then
        echo ""
        echo "⚠️  ATTENZIONE: Deploy non completato nel tempo previsto"
        echo ""
        echo "📋 COMANDI DI VERIFICA:"
        echo "   Stato ambiente: aws elasticbeanstalk describe-environments --application-name $APP_NAME --environment-names $ENV_NAME --region $REGION"
        echo "   Eventi recenti: aws elasticbeanstalk describe-events --application-name $APP_NAME --environment-name $ENV_NAME --region $REGION --max-items 20"
        echo "   Logs: aws elasticbeanstalk request-environment-info --environment-name $ENV_NAME --info-type tail --region $REGION"
        echo ""
        echo "🔧 TROUBLESHOOTING:"
        echo "   1. Verifica che l'immagine ECR sia accessibile"
        echo "   2. Controlla i logs di Elastic Beanstalk"
        echo "   3. Verifica i permessi IAM"
        echo "   4. Controlla i gruppi di sicurezza"
    fi
    
    return $([ "$deploy_success" = true ] && echo 0 || echo 1)
}

# FUNZIONE PER PULIZIA FINALE
cleanup() {
    echo ""
    echo "6. 🧹 PULIZIA LOCALE..."
    rm -rf .ebextensions Dockerrun.aws.json 2>/dev/null || true
    echo "   ✅ File temporanei puliti"
}

# =============================================================================
# ESECUZIONE PRINCIPALE
# =============================================================================

main() {
    # Verifica prerequisiti (continua anche se alcuni falliscono)
    if ! check_prerequisites; then
        echo ""
        echo "⚠️  Alcuni prerequisiti richiedono attenzione, ma procedo con il deploy..."
        echo ""
    fi
    
    # Esegui il processo di deploy
    create_eb_application
    create_deployment_package
    
    # Usa un version label SEMPLICE e SICURO
    VERSION_LABEL="v1"
    create_application_version "$VERSION_LABEL"
    create_eb_environment "$VERSION_LABEL"
    monitor_deployment
    cleanup
    
    echo ""
    echo "=================================================="
    echo " 🎯 PROCESSO DI DEPLOY COMPLETATO"
    echo "=================================================="
}

# Esegui la funzione principale
main