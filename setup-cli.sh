#!/bin/bash

# Interrompe lo script al primo errore
set -e

# =================================================================
# VARIABILI DI CONFIGURAZIONE
# =================================================================

REGION="eu-west-1"
# Le variabili LAMBDA_STACK, ECR_REPO e APP_NAME sono prese dal tuo deploy.sh per coerenza
APP_NAME="film-recommender-final" 
LAMBDA_STACK="$APP_NAME-lambda" 

# Configurazione Cognito (Nomi originali)
COGNITO_USER_POOL_NAME="FilmRecommenderUserPool"
CLIENT_NAME="WebClient"
# Placeholder API (usato nei file prima del deploy)
API_PLACEHOLDER="https://mk9humh7rf.execute-api.eu-west-1.amazonaws.com/Prod"

# Bucket S3 per artefatti SAM/CloudFormation
S3_BUCKET_FULL="sam-deployment-bucket-$REGION-$(aws sts get-caller-identity --query Account --output text)"

echo "======================================================"
echo "⚙️ FASE PRELIMINARE: CREAZIONE INFRASTRUTTURA BASE"
echo "   Regione: $REGION"
echo "======================================================"

# --- 1. CREAZIONE/VERIFICA BUCKET S3 DI DEPLOYMENT ---
echo "1. Creazione o verifica bucket S3 per artefatti SAM..."
aws s3 mb s3://$S3_BUCKET_FULL --region $REGION 2>/dev/null || echo "Bucket S3 $S3_BUCKET_FULL esiste o è stato creato."

# --- 2. CREAZIONE INFRASTRUTTURA SERVERLESS (DynamoDB, SQS, Lambda, API Gateway) ---
# Il file template.yaml definisce DynamoDB, SQS e le funzioni Lambda.
# Utilizziamo SAM/CloudFormation per crearli da terminale.

echo "2. Deploy dello Stack SAM (crea DynamoDB, SQS, Lambda, API Gateway)..."

# Compila l'applicazione Serverless
sam build --template template.yaml || { echo "❌ Errore durante il SAM build."; exit 1; }

# Esegue il deploy dello Stack CloudFormation/SAM
DEPLOY_OUTPUT=$(sam deploy \
    --template-file .aws-sam/build/template.yaml \
    --stack-name $LAMBDA_STACK \
    --s3-bucket $S3_BUCKET_FULL \
    --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND \
    --region $REGION \
    --no-confirm-changeset \
    --query 'Stacks[0].Outputs' --output json)

if [ $? -ne 0 ]; then
    echo "❌ Errore durante il SAM deploy dello stack Lambda ($LAMBDA_STACK)."
    exit 1
fi

# Estrazione dell'URL API Gateway
API_URL=$(echo $DEPLOY_OUTPUT | jq -r '.[] | select(.OutputKey=="ApiUrl").OutputValue')

if [ -z "$API_URL" ]; then
    echo "⚠️ Impossibile trovare l'URL API Gateway dagli output. Uso il placeholder."
    API_URL=$API_PLACEHOLDER
fi
echo "    > URL API Gateway ottenuto: $API_URL"

# --- 3. CREAZIONE COGNITO (Non è in template.yaml) ---

echo "3. Creazione Pool Utenti e Client Cognito..."
# 3.1 Cerca o crea User Pool
USER_POOL_ID=$(aws cognito-idp create-user-pool \
    --pool-name $COGNITO_USER_POOL_NAME \
    --region $REGION \
    --query 'UserPool.Id' --output text 2>/dev/null || \
    aws cognito-idp list-user-pools --region $REGION --max-results 10 --query "UserPools[?Name=='$COGNITO_USER_POOL_NAME'].Id" --output text | head -1)

if [ -z "$USER_POOL_ID" ]; then
    echo "❌ Errore critico: Impossibile creare o trovare User Pool Cognito."
    exit 1
fi
echo "    > User Pool ID: $USER_POOL_ID"

# 3.2 Cerca o crea Client App
CLIENT_ID=$(aws cognito-idp create-user-pool-client \
    --user-pool-id $USER_POOL_ID \
    --client-name "$CLIENT_NAME" \
    --explicit-auth-flows "ALLOW_USER_PASSWORD_AUTH" "ALLOW_USER_SRP_AUTH" \
    --no-generate-secret --region $REGION \
    --query 'UserPoolClient.ClientId' --output text 2>/dev/null || \
    aws cognito-idp list-user-pool-clients --user-pool-id $USER_POOL_ID --region $REGION --query "UserPoolClients[?ClientName=='$CLIENT_NAME'].ClientId" --output text | head -1)

echo "    > Client ID: $CLIENT_ID"

# --- 4. AGGIORNAMENTO CODICE CON PARAMETRI REALI ---
echo "4. Aggiornamento Codice Frontend e Backend con ID reali..."

# Funzione per aggiornare i file (usa 'sed' di Linux o 'sed -i' per macOS)
update_file() {
    FILE=$1
    PATTERN=$2
    REPLACEMENT=$3
    # Verifica il sistema operativo e usa il comando sed appropriato
    if [[ "$OSTYPE" == "darwin"* ]]; then # macOS
        sed -i '' "$PATTERN" "$FILE"
    else # Linux (es. AWS, Docker)
        sed -i "$PATTERN" "$FILE"
    fi
}

# 4.1 Aggiorna static/js/auth.js (Cognito ID)
update_file static/js/auth.js "s/const USER_POOL_ID = \".*\";/const USER_POOL_ID = \"$USER_POOL_ID\";/"
update_file static/js/auth.js "s/const CLIENT_ID = \".*\";/const CLIENT_ID = \"$CLIENT_ID\";/"

# 4.2 Aggiorna application.py (API URL)
update_file application.py "s|API_BASE_URL = os.environ.get('API_GATEWAY_URL', '.*')|API_BASE_URL = os.environ.get('API_GATEWAY_URL', '$API_URL')|"

# 4.3 Aggiorna i file JS con l'API URL
update_file static/js/app.js "s|let API_BASE_URL = '.*';|let API_BASE_URL = '$API_URL';|g"
update_file static/js/dashboard.js "s|let API_BASE_URL = '.*';|let API_BASE_URL = '$API_URL';|g"

# --- 5. ISTRUZIONI FINALI ---
echo "======================================================"
echo "✅ INFRASTRUTTURA BASE CREATA E CODICE AGGIORNATO"
echo "======================================================"
echo "Risorse Create/Aggiornate da SAM:"
echo "  - Tabella DynamoDB: FilmRecommender-Analytics"
echo "  - Code SQS: film-recommender-queue & film-recommender-dlq"
echo "  - Lambda Functions: FilmRecommenderFunction & film-recommender-queue-processor"
echo "  - API Gateway URL: $API_URL"
echo ""
echo "Risorse create da AWS CLI:"
echo "  - User Pool Cognito: $USER_POOL_ID"
echo "  - Client App ID: $CLIENT_ID"
echo ""
echo "PROSSIMI PASSI (OBBLIGATORI):"
echo "1. Salva le modifiche (auth.js, application.py, app.js, dashboard.js) su Git:"
echo '   git add static/js/auth.js application.py static/js/app.js static/js/dashboard.js'
echo '   git commit -m "Config: Update AWS IDs after SAM deployment"'
echo '   git push -u origin main'
echo ""
echo "2. Esegui il tuo script di deployment principale (Docker/EB):"
echo "   ./deploy.sh"