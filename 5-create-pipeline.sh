#!/bin/bash
set -e

echo "======================================================"
echo " 🚀 CREAZIONE PIPELINE CI/CD CON GITHUB"
echo "======================================================"
echo " Configura pipeline automatica per il repository"
echo "======================================================"

# Configurazioni
REGION="eu-west-1"
PIPELINE_BASE_NAME="film-pipe"
GITHUB_OWNER="Matteovullo"
GITHUB_REPO="film-recommender" 
GITHUB_BRANCH="main"

# Configurazioni applicazione
APP_NAME="film-recommender-final"
ENV_NAME="film-recommender-final-env"
LAMBDA_STACK="film-recommender-final-lambda-stack"

# Recupera Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo ""
echo "🎯 CONFIGURAZIONE PIPELINE:"
echo "   Repository: $GITHUB_OWNER/$GITHUB_REPO"
echo "   Branch: $GITHUB_BRANCH"
echo "   Account: $ACCOUNT_ID"
echo "   Region: $REGION"
echo ""

# FUNZIONE: Trova prossima versione pipeline
find_next_pipeline_version() {
    local max_version=0
    
    local stacks=$(aws cloudformation list-stacks --region $REGION \
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
        --query "StackSummaries[?contains(StackName, '$PIPELINE_BASE_NAME')].StackName" \
        --output text 2>/dev/null || true)
    
    for stack in $stacks; do
        if [[ $stack =~ $PIPELINE_BASE_NAME-(v[0-9]+) ]]; then
            local version=${BASH_REMATCH[1]#v}
            if [ $version -gt $max_version ]; then
                max_version=$version
            fi
        fi
    done
    
    echo "v$((max_version + 1))"
}

PIPELINE_VERSION=$(find_next_pipeline_version)
PIPELINE_STACK_NAME="$PIPELINE_BASE_NAME-$PIPELINE_VERSION"

echo "📦 CREAZIONE PIPELINE: $PIPELINE_STACK_NAME"

# FUNZIONE: Richiedi GitHub Token
get_github_token() {
    echo ""
    echo "🔐 CONFIGURAZIONE GITHUB TOKEN"
    echo "   Per collegare GitHub a CodePipeline, serve un Personal Access Token"
    echo ""
    echo "💡 ISTRUZIONI PER CREARE IL TOKEN:"
    echo "   1. Vai su GitHub > Settings > Developer settings > Personal access tokens"
    echo "   2. Clicca 'Generate new token'"
    echo "   3. Dai un nome (es: 'aws-codepipeline')"
    echo "   4. Seleziona scopes: repo, admin:repo_hook"
    echo "   5. Clicca 'Generate token'"
    echo "   6. COPIA il token (lo vedrai solo una volta!)"
    echo ""
    
    read -p "   Inserisci il GitHub Personal Access Token: " GITHUB_TOKEN
    
    if [ -z "$GITHUB_TOKEN" ]; then
        echo "❌ Token GitHub non fornito"
        exit 1
    fi
    
    # Verifica base del token (deve iniziare con ghp_)
    if [[ ! $GITHUB_TOKEN =~ ^ghp_ ]]; then
        echo "⚠️  Il token non sembra valido (dovrebbe iniziare con 'ghp_')"
        read -p "   Continuare comunque? (s/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Ss]$ ]]; then
            exit 1
        fi
    fi
    
    export GITHUB_TOKEN
}

# FUNZIONE: Verifica che il template esista
verify_template() {
    if [ ! -f "pipeline-template.yaml" ]; then
        echo "❌ ERRORE: pipeline-template.yaml non trovato"
        echo "   Assicurati che il file template sia nella directory corrente"
        exit 1
    fi
    echo "✅ Template pipeline trovato"
}

# FUNZIONE: Verifica prerequisiti
check_prerequisites() {
    echo ""
    echo "🔍 VERIFICA PREREQUISITI..."
    
    # Verifica AWS CLI
    if ! command -v aws &> /dev/null; then
        echo "❌ AWS CLI non installato"
        exit 1
    fi
    
    # Verifica credenziali AWS
    if ! aws sts get-caller-identity &> /dev/null; then
        echo "❌ Credenziali AWS non configurate"
        exit 1
    fi
    
    echo "✅ AWS CLI e credenziali OK"
}

# FUNZIONE: Deploy pipeline
deploy_pipeline() {
    echo ""
    echo "🚀 DEPLOY PIPELINE IN CORSO..."
    
    aws cloudformation deploy \
        --template-file pipeline-template.yaml \
        --stack-name "$PIPELINE_STACK_NAME" \
        --parameter-overrides \
            GitHubOwner="$GITHUB_OWNER" \
            GitHubRepo="$GITHUB_REPO" \
            GitHubBranch="$GITHUB_BRANCH" \
            GitHubToken="$GITHUB_TOKEN" \
            EBApplicationName="$APP_NAME" \
            EBEnvironmentName="$ENV_NAME" \
            LambdaStackName="$LAMBDA_STACK" \
            PipelineVersion="$PIPELINE_VERSION" \
        --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
        --region $REGION
    
    echo "✅ Pipeline deploy completato"
}

# FUNZIONE: Verifica stato pipeline
verify_pipeline() {
    echo ""
    echo "🔍 VERIFICA STATO PIPELINE..."
    
    # Attendi che la pipeline sia creata
    sleep 10
    
    # Verifica che la pipeline esista
    if aws codepipeline get-pipeline --name "film-pipe-$PIPELINE_VERSION" --region $REGION &>/dev/null; then
        echo "✅ Pipeline creata con successo"
        
        # Trigger prima esecuzione
        echo "🚀 Avvio prima esecuzione pipeline..."
        aws codepipeline start-pipeline-execution \
            --name "film-pipe-$PIPELINE_VERSION" \
            --region $REGION
            
        echo "✅ Prima esecuzione avviata"
    else
        echo "⚠️  Pipeline creata ma non immediatamente disponibile"
    fi
}

# FUNZIONE: Mostra informazioni
show_info() {
    echo ""
    echo "======================================================"
    echo " ✅ PIPELINE CI/CD CREATA CON SUCCESSO"
    echo "======================================================"
    echo ""
    echo "📋 INFORMAZIONI PIPELINE:"
    echo "   📛 Nome Stack: $PIPELINE_STACK_NAME"
    echo "   🔢 Versione: $PIPELINE_VERSION"
    echo "   📦 Build Project: film-build-$PIPELINE_VERSION"
    echo "   🪣 S3 Bucket: film-pipe-$PIPELINE_VERSION-$ACCOUNT_ID"
    echo ""
    echo "🌐 URL CONSOLE:"
    echo "   Pipeline: https://$REGION.console.aws.amazon.com/codesuite/codepipeline/pipelines/film-pipe-$PIPELINE_VERSION/view"
    echo "   CodeBuild: https://$REGION.console.aws.amazon.com/codesuite/codebuild/projects/film-build-$PIPELINE_VERSION"
    echo ""
    echo "🔧 COMPONENTI CONFIGURATI:"
    echo "   ✅ CodePipeline con trigger GitHub"
    echo "   ✅ CodeBuild con permessi completi"
    echo "   ✅ S3 Artifact Store"
    echo "   ✅ Deploy automatico a Elastic Beanstalk"
    echo "   ✅ Deploy automatico Lambda/API Gateway"
    echo ""
    echo "🚀 PROSSIMI PASSI:"
    echo "   1. La pipeline si attiverà al prossimo commit su GitHub"
    echo "   2. Puoi monitorare lo stato nella console AWS"
    echo "   3. Per trigger manuale: aws codepipeline start-pipeline-execution --name film-pipe-$PIPELINE_VERSION"
    echo ""
    echo "📝 NOTE:"
    echo "   - Il primo deploy potrebbe richiedere 15-20 minuti"
    echo "   - I successivi deploy saranno molto più veloci"
    echo "   - La pipeline gestirà automaticamente aggiornamenti futuri"
    echo "======================================================"
}

# FUNZIONE: Gestione errori
handle_error() {
    echo ""
    echo "❌ ERRORE durante la creazione della pipeline"
    echo "💡 TROUBLESHOOTING:"
    echo "   - Verifica che il GitHub Token sia valido"
    echo "   - Controlla che il repository GitHub esista"
    echo "   - Verifica i permessi IAM dell'utente AWS"
    echo "   - Controlla i logs di CloudFormation"
    echo ""
    echo "🔧 COMANDI DI DEBUG:"
    echo "   aws cloudformation describe-stack-events --stack-name $PIPELINE_STACK_NAME --region $REGION"
    echo "   aws cloudformation describe-stacks --stack-name $PIPELINE_STACK_NAME --region $REGION"
}

# FUNZIONE PRINCIPALE
main() {
    # Imposta trap per gestione errori
    trap handle_error ERR
    
    check_prerequisites
    verify_template
    get_github_token
    deploy_pipeline
    verify_pipeline
    show_info
}

# Esegui
main