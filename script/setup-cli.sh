set -e

REGION="eu-west-1"
APP_NAME="film-recommender-final"
LAMBDA_STACK="$APP_NAME-lambda"
COGNITO_USER_POOL_NAME="FilmRecommenderUserPool"
CLIENT_NAME="WebClient"
API_PLACEHOLDER="https://mk9humh7rf.execute-api.eu-west-1.amazonaws.com/Prod"
TEST_USER_EMAIL="test@filmrecommender.com"
TEST_USER_PASSWORD="Password123!"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
S3_BUCKET_FULL="sam-deployment-bucket-$REGION-$ACCOUNT_ID"

echo "======================================================"
echo " FASE PRELIMINARE: CREAZIONE INFRASTRUTTURA BASE"
echo "======================================================"
echo " Regione: $REGION"
echo "------------------------------------------------------"

echo "1. Creazione o verifica bucket S3 per artefatti SAM..."
aws s3 mb s3://$S3_BUCKET_FULL --region $REGION 2>/dev/null || echo "Bucket S3 $S3_BUCKET_FULL esiste o è stato creato."

echo "2. Deploy dello Stack SAM (crea DynamoDB, SQS, Lambda, API Gateway)..."

sam build --template template.yaml || { echo "Errore durante il SAM build."; exit 1; }

sam deploy \
    --template-file .aws-sam/build/template.yaml \
    --stack-name $LAMBDA_STACK \
    --s3-bucket $S3_BUCKET_FULL \
    --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND \
    --region $REGION \
    --no-confirm-changeset 

if [ $? -ne 0 ]; then
    echo "Errore durante il SAM deploy dello stack Lambda ($LAMBDA_STACK)."
    exit 1
fi

API_URL=$(aws cloudformation describe-stacks \
    --stack-name $LAMBDA_STACK \
    --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' \
    --output text)

if [ -z "$API_URL" ]; then
    echo "Impossibile trovare l'URL API Gateway dagli output. Uso il placeholder."
    API_URL=$API_PLACEHOLDER
fi
echo "    > URL API Gateway ottenuto: $API_URL"

echo "3. Creazione Pool Utenti e Client Cognito..."

USER_POOL_ID=$(aws cognito-idp list-user-pools --region $REGION --max-results 10 --query "UserPools[?Name=='$COGNITO_USER_POOL_NAME'].Id" --output text | head -1)

if [ -z "$USER_POOL_ID" ]; then
    USER_POOL_ID=$(aws cognito-idp create-user-pool \
        --pool-name $COGNITO_USER_POOL_NAME \
        --region $REGION \
        --query 'UserPool.Id' --output text)
    echo "    > User Pool creato: $USER_POOL_ID"
fi

if [ -z "$USER_POOL_ID" ]; then
    echo "Errore critico: Impossibile creare o trovare User Pool Cognito."
    exit 1
fi
echo "    > User Pool ID: $USER_POOL_ID"

echo "3.1.5 Aggiornamento policy di verifica del Pool Utenti..."

aws cognito-idp update-user-pool \
    --user-pool-id $USER_POOL_ID \
    --auto-verified-attributes "email" \
    --verification-message-template '{"DefaultEmailOption":"CONFIRM_WITH_CODE", "EmailSubject":"Il tuo codice di verifica", "EmailMessage":"Il codice di verifica è {####}"}' \
    --region $REGION > /dev/null || echo "Impossibile aggiornare la policy di verifica."


CLIENT_ID=$(aws cognito-idp list-user-pool-clients --user-pool-id $USER_POOL_ID --region $REGION --query "UserPoolClients[?ClientName=='$CLIENT_NAME'].ClientId" --output text | head -1)

if [ -z "$CLIENT_ID" ]; then
    CLIENT_ID=$(aws cognito-idp create-user-pool-client \
        --user-pool-id $USER_POOL_ID \
        --client-name "$CLIENT_NAME" \
        --explicit-auth-flows "ALLOW_USER_PASSWORD_AUTH" "ALLOW_USER_SRP_AUTH" \
        --no-generate-secret --region $REGION \
        --query 'UserPoolClient.ClientId' --output text)
    echo "    > Client App creato: $CLIENT_ID"
fi

echo "    > Client ID: $CLIENT_ID"

echo "3.3 Creazione e Conferma dell'utente di test ($TEST_USER_EMAIL)..."

if ! aws cognito-idp admin-get-user --user-pool-id $USER_POOL_ID --username $TEST_USER_EMAIL --region $REGION 2>/dev/null; then
    aws cognito-idp admin-create-user \
        --user-pool-id $USER_POOL_ID \
        --username $TEST_USER_EMAIL \
        --user-attributes Name="email",Value="$TEST_USER_EMAIL" \
        --temporary-password "$TEST_USER_PASSWORD" \
        --region $REGION > /dev/null
    
    aws cognito-idp admin-set-user-password \
        --user-pool-id $USER_POOL_ID \
        --username $TEST_USER_EMAIL \
        --password "$TEST_USER_PASSWORD" \
        --permanent \
        --region $REGION > /dev/null
    echo "    Utente creato e confermato."
else
    echo "    Utente $TEST_USER_EMAIL esiste già. Ignoro la creazione."
fi

echo "4. Aggiornamento Codice Frontend e Backend con ID reali..."

update_file() {
    FILE=$1
    PATTERN=$2
    REPLACEMENT=$3
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "$PATTERN" "$FILE"
    else 
        sed -i "$PATTERN" "$FILE"
    fi
}

update_file static/js/auth.js "s/const USER_POOL_ID = \".*\";/const USER_POOL_ID = \"$USER_POOL_ID\";/"
update_file static/js/auth.js "s/const CLIENT_ID = \".*\";/const CLIENT_ID = \"$CLIENT_ID\";/"

update_file application.py "s|API_BASE_URL = os.environ.get('API_GATEWAY_URL', '.*')|API_BASE_URL = os.environ.get('API_GATEWAY_URL', '$API_URL')|"

update_file static/js/app.js "s|let API_BASE_URL = '.*';|let API_BASE_URL = '$API_URL';|g"

echo "======================================================"
echo " INFRASTRUTTURA BASE CREATA E CODICE AGGIORNATO"
echo "======================================================"
echo "Risorse Create/Aggiornate da SAM:"
echo "  - Tabella DynamoDB: FilmRecommender-Analytics-v2"
echo "  - Code SQS: film-recommender-v2-queue & film-recommender-v2-dlq"
echo "  - Lambda Functions: FilmRecommenderFunction & film-recommender-queue-processor"
echo "  - API Gateway URL: $API_URL"
echo ""
echo "Risorse create da AWS CLI:"
echo "  - User Pool Cognito: $USER_POOL_ID"
echo "  - Client App ID: $CLIENT_ID"
echo "  - Utente Test: $TEST_USER_EMAIL (Password: $TEST_USER_PASSWORD)"
echo ""
echo "PROSSIMI PASSI (OBBLIGATORI):"
echo "1. Salva le modifiche (auth.js, application.py, app.js) su Git se stai usando un repository."
echo ""
echo "2. Esegui il tuo script di deployment principale (Docker/EB):"
echo "   ./deploy.sh"