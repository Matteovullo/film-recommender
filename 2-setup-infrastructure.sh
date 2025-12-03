#!/bin/bash
set -e

echo "======================================================"
echo " 🔧 FIX COMPLETO COGNITO USER POOL"
echo "======================================================"
echo " Risolve: 'User pool eu-west-1_Gx1rUSirL does not exist'"
echo "======================================================"

REGION="eu-west-1"
ACCOUNT_ID="023048164072"
APP_NAME="film-recommender-final"
COGNITO_USER_POOL_NAME="FilmRecommenderUserPool"
TEST_USER_EMAIL="test@filmrecommender.com"
TEST_USER_PASSWORD="Password123!"

# Colori per output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Funzioni di logging
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_info() { echo -e "ℹ️  $1"; }

# 1. VERIFICA USER POOL ESISTENTE
echo ""
log_info "1. Verifica User Pool Cognito..."

EXISTING_POOL=$(aws cognito-idp list-user-pools --region $REGION --max-results 20 \
    --query "UserPools[?contains(Name, 'FilmRecommender') || contains(Name, '$COGNITO_USER_POOL_NAME')].Id" \
    --output text 2>/dev/null || echo "")

if [ -n "$EXISTING_POOL" ]; then
    USER_POOL_ID="$EXISTING_POOL"
    POOL_NAME=$(aws cognito-idp describe-user-pool --user-pool-id $USER_POOL_ID --region $REGION --query 'UserPool.Name' --output text 2>/dev/null || echo "Unknown")
    log_success "Trovato User Pool esistente: $POOL_NAME ($USER_POOL_ID)"
else
    log_warning "Nessun User Pool trovato, creazione nuovo..."
    
    # 2. CREA NUOVO USER POOL
    echo ""
    log_info "2. Creazione nuovo User Pool..."
    
    USER_POOL_ID=$(aws cognito-idp create-user-pool \
        --pool-name $COGNITO_USER_POOL_NAME \
        --region $REGION \
        --auto-verified-attributes email \
        --policies '{
            "PasswordPolicy": {
                "MinimumLength": 8,
                "RequireUppercase": true,
                "RequireLowercase": true,
                "RequireNumbers": true,
                "RequireSymbols": false
            }
        }' \
        --schema '[
            {
                "Name": "email",
                "AttributeDataType": "String",
                "Required": true
            }
        ]' \
        --query 'UserPool.Id' --output text 2>/dev/null)
    
    if [ -z "$USER_POOL_ID" ]; then
        log_error "Impossibile creare User Pool!"
        exit 1
    fi
    
    log_success "Nuovo User Pool creato: $USER_POOL_ID"
fi

# 3. VERIFICA/CREA CLIENT
echo ""
log_info "3. Configurazione Client Cognito..."

CLIENT_ID=$(aws cognito-idp list-user-pool-clients \
    --user-pool-id $USER_POOL_ID \
    --region $REGION \
    --max-results 10 \
    --query 'UserPoolClients[0].ClientId' \
    --output text 2>/dev/null || echo "")

if [ -z "$CLIENT_ID" ] || [ "$CLIENT_ID" == "None" ]; then
    log_warning "Nessun Client trovato, creazione nuovo..."
    
    CLIENT_ID=$(aws cognito-idp create-user-pool-client \
        --user-pool-id $USER_POOL_ID \
        --client-name "WebClient" \
        --explicit-auth-flows "ALLOW_USER_PASSWORD_AUTH" "ALLOW_USER_SRP_AUTH" "ALLOW_REFRESH_TOKEN_AUTH" \
        --no-generate-secret \
        --region $REGION \
        --query 'UserPoolClient.ClientId' --output text 2>/dev/null)
    
    if [ -n "$CLIENT_ID" ]; then
        log_success "Nuovo Client creato: $CLIENT_ID"
    else
        log_error "Impossibile creare Client!"
        exit 1
    fi
else
    log_success "Client esistente trovato: $CLIENT_ID"
fi

# 4. CREA/AGGIORNA UTENTE TEST
echo ""
log_info "4. Configurazione utente test..."

# Verifica se l'utente esiste già
USER_EXISTS=$(aws cognito-idp admin-get-user \
    --user-pool-id $USER_POOL_ID \
    --username "$TEST_USER_EMAIL" \
    --region $REGION 2>/dev/null && echo "yes" || echo "no")

if [ "$USER_EXISTS" = "no" ]; then
    log_info "Creazione utente test: $TEST_USER_EMAIL"
    
    aws cognito-idp admin-create-user \
        --user-pool-id $USER_POOL_ID \
        --username "$TEST_USER_EMAIL" \
        --user-attributes Name="email",Value="$TEST_USER_EMAIL" Name="email_verified",Value="true" \
        --temporary-password "$TEST_USER_PASSWORD" \
        --message-action SUPPRESS \
        --region $REGION > /dev/null 2>&1 || log_warning "Possibile errore creazione utente"
    
    # Imposta password permanente
    aws cognito-idp admin-set-user-password \
        --user-pool-id $USER_POOL_ID \
        --username "$TEST_USER_EMAIL" \
        --password "$TEST_USER_PASSWORD" \
        --permanent \
        --region $REGION > /dev/null 2>&1 || log_warning "Possibile errore impostazione password"
    
    log_success "Utente test creato"
else
    log_success "Utente test già esistente"
fi

# 5. AGGIORNAMENTO FILE AUTH.JS (CRITICO!)
echo ""
log_info "5. Aggiornamento file di configurazione..."

# AGGIORNA AUTH.JS
if [ -f "static/js/auth.js" ]; then
    log_info "Aggiornamento static/js/auth.js..."
    
    # Crea backup
    TIMESTAMP=$(date +%Y%m%d%H%M%S)
    cp static/js/auth.js "static/js/auth.js.backup-$TIMESTAMP"
    
    # Aggiorna USER_POOL_ID
    if grep -q "USER_POOL_ID = " static/js/auth.js; then
        sed -i.bak "s|const USER_POOL_ID = '.*';|const USER_POOL_ID = '$USER_POOL_ID';|g" static/js/auth.js
        log_success "USER_POOL_ID aggiornato: $USER_POOL_ID"
    else
        log_error "Variabile USER_POOL_ID non trovata in auth.js!"
    fi
    
    # Aggiorna CLIENT_ID
    if grep -q "CLIENT_ID = " static/js/auth.js; then
        sed -i.bak "s|const CLIENT_ID = '.*';|const CLIENT_ID = '$CLIENT_ID';|g" static/js/auth.js
        log_success "CLIENT_ID aggiornato: $CLIENT_ID"
    else
        log_error "Variabile CLIENT_ID non trovata in auth.js!"
    fi
    
    # Pulisci backup temporanei
    rm -f static/js/auth.js.bak 2>/dev/null || true
    
    # Verifica aggiornamento
    echo ""
    log_info "Verifica aggiornamento auth.js:"
    grep "USER_POOL_ID = " static/js/auth.js
    grep "CLIENT_ID = " static/js/auth.js
else
    log_error "File static/js/auth.js non trovato!"
    exit 1
fi

# 6. AGGIORNA APPLICATION.PY (opzionale ma utile)
echo ""
log_info "6. Aggiornamento application.py..."

if [ -f "application.py" ]; then
    # Rimuovi vecchie configurazioni Cognito se esistono
    sed -i.bak '/COGNITO_USER_POOL_ID/d' application.py 2>/dev/null || true
    sed -i.bak '/COGNITO_CLIENT_ID/d' application.py 2>/dev/null || true
    sed -i.bak '/COGNITO_REGION/d' application.py 2>/dev/null || true
    
    # Aggiungi nuove configurazioni dopo gli imports
    IMPORT_LINE=$(grep -n "^import\|^from" application.py | tail -1 | cut -d: -f1 2>/dev/null || echo "0")
    
    if [ "$IMPORT_LINE" -gt 0 ]; then
        sed -i.bak "${IMPORT_LINE}a\\
# Cognito Configuration (Auto-generated by fix script)\\
COGNITO_USER_POOL_ID = '$USER_POOL_ID'\\
COGNITO_CLIENT_ID = '$CLIENT_ID'\\
COGNITO_REGION = '$REGION'\\
" application.py
    else
        sed -i.bak "1i\\
# Cognito Configuration (Auto-generated by fix script)\\
COGNITO_USER_POOL_ID = '$USER_POOL_ID'\\
COGNITO_CLIENT_ID = '$CLIENT_ID'\\
COGNITO_REGION = '$REGION'\\
" application.py
    fi
    
    rm -f application.py.bak 2>/dev/null || true
    log_success "application.py aggiornato"
else
    log_warning "File application.py non trovato (skippato)"
fi

# 7. REBUILD E REDEPLOY DOCKER
echo ""
log_info "7. Preparazione per rebuild Docker..."

ECR_URL="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/film-recommender"

# Verifica che ECR esista
if aws ecr describe-repositories --repository-names film-recommender --region $REGION &>/dev/null; then
    log_success "Repository ECR trovato: $ECR_URL"
    
    echo ""
    log_info "Per completare il fix, esegui questi comandi:"
    echo ""
    echo "1. Login ECR:"
    echo "   aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_URL"
    echo ""
    echo "2. Build immagine Docker:"
    echo "   docker build -t film-recommender ."
    echo ""
    echo "3. Tag e push:"
    echo "   docker tag film-recommender:latest $ECR_URL:latest"
    echo "   docker push $ECR_URL:latest"
    echo ""
    echo "4. Aggiorna Elastic Beanstalk:"
    echo "   aws elasticbeanstalk create-application-version \\"
    echo "     --application-name '$APP_NAME' \\"
    echo "     --region '$REGION' \\"
    echo "     --version-label 'v-cognito-fix-$(date +%Y%m%d%H%M%S)' \\"
    echo "     --source-bundle S3Bucket='elasticbeanstalk-$REGION-$ACCOUNT_ID',S3Key='deployment.zip'"
    echo ""
    echo "   aws elasticbeanstalk update-environment \\"
    echo "     --application-name '$APP_NAME' \\"
    echo "     --environment-name '$APP_NAME-env' \\"
    echo "     --version-label 'v-cognito-fix-$(date +%Y%m%d%H%M%S)' \\"
    echo "     --region '$REGION'"
    echo ""
else
    log_warning "Repository ECR non trovato, potrebbe essere necessario ricrearlo"
fi

# 8. CREA SCRIPT AUTOMATICO PER REDEPLOY
echo ""
log_info "8. Creazione script automatico per redeploy..."

cat > redeploy-with-cognito-fix.sh << EOF
#!/bin/bash
set -e

echo "======================================================"
echo " 🚀 REDEPLOY CON FIX COGNITO"
echo "======================================================"

REGION="eu-west-1"
ECR_URL="023048164072.dkr.ecr.eu-west-1.amazonaws.com/film-recommender"
APP_NAME="film-recommender-final"

# Login ECR
echo "1. Login ECR..."
aws ecr get-login-password --region \$REGION | docker login --username AWS --password-stdin \$ECR_URL

# Build
echo "2. Build immagine Docker..."
docker build -t film-recommender .

# Tag e push
echo "3. Tagging e push..."
docker tag film-recommender:latest \$ECR_URL:latest
docker push \$ECR_URL:latest

# Crea nuova versione EB
VERSION_LABEL="v-cognito-fix-\$(date +%Y%m%d%H%M%S)"
S3_BUCKET="elasticbeanstalk-\$REGION-023048164072"

echo "4. Creazione versione Elastic Beanstalk: \$VERSION_LABEL"
aws elasticbeanstalk create-application-version \\
  --application-name "\$APP_NAME" \\
  --region "\$REGION" \\
  --version-label "\$VERSION_LABEL" \\
  --source-bundle S3Bucket="\$S3_BUCKET",S3Key="deployment.zip"

# Aggiorna environment
echo "5. Aggiornamento environment..."
aws elasticbeanstalk update-environment \\
  --application-name "\$APP_NAME" \\
  --environment-name "\$APP_NAME-env" \\
  --version-label "\$VERSION_LABEL" \\
  --region "\$REGION"

echo ""
echo "======================================================"
echo " ✅ REDEPLOY AVVIATO"
echo "======================================================"
echo "Monitora lo stato con:"
echo "aws elasticbeanstalk describe-environments \\"
echo "  --application-name \$APP_NAME \\"
echo "  --environment-names \$APP_NAME-env \\"
echo "  --region \$REGION \\"
echo "  --query 'Environments[0].{Status:Status,Health:Health,Version:VersionLabel}'"
echo ""
echo "🌐 URL: http://film-recommender-final-env.eba-pzkfbqzv.eu-west-1.elasticbeanstalk.com"
echo "======================================================"
EOF

chmod +x redeploy-with-cognito-fix.sh
log_success "Script creato: redeploy-with-cognito-fix.sh"

# 9. RIASSUNTO FINALE
echo ""
echo "======================================================"
echo " ✅ FIX COGNITO COMPLETATO"
echo "======================================================"
echo ""
echo "📋 CONFIGURAZIONI APPLICATE:"
echo "   🔐 Cognito User Pool: $USER_POOL_ID"
echo "   🔑 Cognito Client: $CLIENT_ID"
echo "   👤 Utente test: $TEST_USER_EMAIL"
echo "   🔓 Password: $TEST_USER_PASSWORD"
echo ""
echo "📁 FILE AGGIORNATI:"
echo "   ✅ static/js/auth.js (backup: static/js/auth.js.backup-$TIMESTAMP)"
if [ -f "application.py" ]; then
    echo "   ✅ application.py"
fi
echo ""
echo "🚀 PER COMPLETARE IL FIX:"
echo "   1. Esegui: ./redeploy-with-cognito-fix.sh"
echo "   2. Attendi 5-10 minuti per il deploy"
echo ""
echo "🔍 PER VERIFICARE:"
echo "   Visita: http://film-recommender-final-env.eba-pzkfbqzv.eu-west-1.elasticbeanstalk.com"
echo "   Usa credenziali: $TEST_USER_EMAIL / $TEST_USER_PASSWORD"
echo ""
echo "⚠️  NOTA IMPORTANTE:"
echo "   Se continui a vedere errori, potrebbe essere necessario"
echo "   cancellare la cache del browser o usare la modalità privata"
echo "======================================================"