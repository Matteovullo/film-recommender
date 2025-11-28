#!/bin/bash
set -e

echo "======================================================"
echo " 🔄 CREAZIONE PIPELINE CI/CD - AMBIENTE DI TEST"
echo "======================================================"
echo " Pipeline completa con tutti i permessi"
echo "======================================================"

# Carica configurazione
if [ -f "./pipeline-config.sh" ]; then
    source ./pipeline-config.sh
else
    echo "⚠️  File pipeline-config.sh non trovato, uso valori di default"
    REGION="eu-west-1"
    GITHUB_OWNER="tuo-username"
    GITHUB_REPO="film-recommender"
    GITHUB_BRANCH="main"
    GITHUB_TOKEN="tuo-token"
    APP_NAME="film-recommender-final"
    ENV_NAME="film-recommender-final-env"
    LAMBDA_STACK="film-recommender-final-lambda"
fi

PIPELINE_BASE_NAME="film-pipe"

# Trova la prossima versione
find_next_version() {
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

PIPELINE_VERSION=$(find_next_version)
PIPELINE_STACK_NAME="$PIPELINE_BASE_NAME-$PIPELINE_VERSION"

echo ""
echo "🎯 CREAZIONE NUOVA PIPELINE: $PIPELINE_STACK_NAME"

# Verifica che il template esista
if [ ! -f "pipeline-template.yaml" ]; then
    echo "❌ ERRORE: pipeline-template.yaml non trovato"
    exit 1
fi

# Deploy pipeline
echo ""
echo "🚀 DEPLOY IN CORSO..."
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

echo ""
echo "======================================================"
echo " ✅ PIPELINE CI/CD CREATA CON SUCCESSO"
echo "======================================================"
echo ""
echo "📋 INFORMAZIONI PIPELINE:"
echo "   📛 Nome: $PIPELINE_STACK_NAME"
echo "   🔢 Versione: $PIPELINE_VERSION"
echo "   🌐 Console: https://$REGION.console.aws.amazon.com/codesuite/codepipeline/pipelines/$PIPELINE_STACK_NAME/view"
echo ""
echo "⚙️  PERMESSI CONFIGURATI:"
echo "   ✅ AutoScalingFullAccess"
echo "   ✅ AmazonEC2FullAccess"
echo "   ✅ AWSElasticBeanstalkFullAccess"
echo "   ✅ AmazonEC2ContainerRegistryPowerUser"
echo "   ✅ AdministratorAccess (per testing)"
echo ""
echo "🔧 COMPONENTI:"
echo "   ✅ CodePipeline: $PIPELINE_STACK_NAME"
echo "   ✅ CodeBuild: film-build-$PIPELINE_VERSION"
echo "   ✅ S3 Bucket: film-pipe-$PIPELINE_VERSION-$ACCOUNT_ID"
echo ""
echo "🚀 LA PIPELINE SI ATTIVERÀ AUTOMATICAMENTE AL PROSSIMO COMMIT"
echo "======================================================"