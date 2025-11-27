#!/bin/bash
set -e

echo "======================================================"
echo " 🔄 CREAZIONE PIPELINE CI/CD"
echo "======================================================"

# Carica configurazione
source ./pipeline-config.sh

# Usa nome base più corto
PIPELINE_BASE_NAME="film-pipe"

# Funzione per eliminare definitivamente stack bloccati
force_delete_stack() {
    local stack_name=$1
    echo " - Eliminazione: $stack_name"
    
    # Elimina risorse dipendenti manualmente
    # CodePipeline
    if aws codepipeline get-pipeline --name "$stack_name" --region $REGION &>/dev/null; then
        aws codepipeline delete-pipeline --name "$stack_name" --region $REGION
        echo "   CodePipeline eliminata"
    fi
    
    # CodeBuild - gestisci diversi pattern di nomi
    local build_name="${stack_name//pipeline/build}"
    build_name="${build_name//film-rec-pipe/film-rec-build}"
    build_name="${build_name//film-recommender-pipeline/film-rec-build}"
    build_name="${build_name//film-pipe/film-build}"
    
    if aws codebuild batch-get-projects --names "$build_name" --region $REGION --query "projects[0]" --output text &>/dev/null; then
        aws codebuild delete-project --name "$build_name" --region $REGION
        echo "   CodeBuild eliminato"
    fi
    
    # Bucket S3
    local bucket_name="$stack_name-$ACCOUNT_ID"
    if aws s3 ls "s3://$bucket_name" --region $REGION &>/dev/null; then
        aws s3 rm "s3://$bucket_name" --recursive --region $REGION 2>/dev/null || true
        aws s3 rb "s3://$bucket_name" --force --region $REGION 2>/dev/null || true
        echo "   Bucket S3 eliminato"
    fi
    
    # Prova l'eliminazione stack
    aws cloudformation delete-stack --stack-name "$stack_name" --region $REGION 2>/dev/null || true
    
    # Attendi breve periodo
    sleep 5
}

# Pulisci tutti gli stack bloccati prima
echo "Pulizia stack bloccati..."
FAILED_STACKS=$(aws cloudformation list-stacks --region $REGION --stack-status-filter DELETE_FAILED --query "StackSummaries[?contains(StackName, 'film-')].StackName" --output text 2>/dev/null || true)

if [ -n "$FAILED_STACKS" ]; then
    for stack in $FAILED_STACKS; do
        force_delete_stack "$stack"
    done
    sleep 10
fi

# Trova la prossima versione
find_next_version() {
    local max_version=0
    
    # Cerca stack attivi
    local stacks=$(aws cloudformation list-stacks --region $REGION --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --query "StackSummaries[?contains(StackName, '$PIPELINE_BASE_NAME')].StackName" --output text 2>/dev/null || true)
    
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

echo "Creazione pipeline: $PIPELINE_STACK_NAME"

# Verifica che lo stack non esista già
if aws cloudformation describe-stacks --stack-name "$PIPELINE_STACK_NAME" --region $REGION &>/dev/null; then
    echo " - Stack già esistente, elimino..."
    force_delete_stack "$PIPELINE_STACK_NAME"
    sleep 10
fi

# Deploy pipeline
echo " - Deploy in corso..."
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

echo "======================================================"
echo " ✅ PIPELINE CREATA CON SUCCESSO"
echo "======================================================"
echo "Nome: $PIPELINE_STACK_NAME"
echo "Console: https://$REGION.console.aws.amazon.com/codesuite/codepipeline/pipelines/$PIPELINE_STACK_NAME/view"