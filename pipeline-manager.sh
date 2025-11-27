#!/bin/bash
set -e

REGION="eu-west-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
APP_NAME="film-recommender-final"
PIPELINE_BASE_NAME="film-recommender-pipeline"

echo "======================================================"
echo " GESTIONE PIPELINE DINAMICA"
echo "======================================================"

# Trova la pipeline esistente più recente
find_existing_pipeline() {
    local latest_pipeline=""
    local latest_version=0
    
    # Cerca tra gli stack CloudFormation
    for stack in $(aws cloudformation list-stacks --region $REGION --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --query "StackSummaries[?contains(StackName, '$PIPELINE_BASE_NAME')].StackName" --output text 2>/dev/null); do
        if [[ $stack =~ $PIPELINE_BASE_NAME-(v[0-9]+) ]]; then
            local version=${BASH_REMATCH[1]#v}
            if [ $version -gt $latest_version ]; then
                latest_version=$version
                latest_pipeline=$stack
            fi
        fi
    done
    
    echo "$latest_pipeline"
}

# Trova la prossima versione della pipeline
get_next_pipeline_version() {
    local existing_pipeline=$(find_existing_pipeline)
    local next_version=1
    
    if [ -n "$existing_pipeline" ]; then
        if [[ $existing_pipeline =~ $PIPELINE_BASE_NAME-(v[0-9]+) ]]; then
            local current_version=${BASH_REMATCH[1]#v}
            next_version=$((current_version + 1))
        fi
    fi
    
    echo "v$next_version"
}

# Elimina pipeline esistente
delete_existing_pipeline() {
    local pipeline_name=$1
    
    if [ -z "$pipeline_name" ]; then
        echo "Nessuna pipeline esistente trovata."
        return 0
    fi
    
    echo "Eliminazione pipeline esistente: $pipeline_name"
    
    # Estrai il numero di versione per trovare le risorse correlate
    local version=""
    if [[ $pipeline_name =~ $PIPELINE_BASE_NAME-(v[0-9]+) ]]; then
        version=${BASH_REMATCH[1]}
    fi
    
    # 1. Elimina la pipeline CodePipeline
    echo " - Eliminazione CodePipeline..."
    aws codepipeline delete-pipeline --name "$pipeline_name" --region $REGION 2>/dev/null || echo "   CodePipeline non trovata o già eliminata"
    
    # 2. Elimina il progetto CodeBuild
    local codebuild_name="${pipeline_name//pipeline/build}"
    echo " - Eliminazione CodeBuild: $codebuild_name..."
    aws codebuild delete-project --name "$codebuild_name" --region $REGION 2>/dev/null || echo "   CodeBuild non trovato o già eliminato"
    
    # 3. Svuota e elimina il bucket S3
    local bucket_name="$pipeline_name-$ACCOUNT_ID"
    echo " - Pulizia bucket S3: $bucket_name..."
    if aws s3 ls "s3://$bucket_name" --region $REGION 2>/dev/null; then
        aws s3 rm "s3://$bucket_name" --recursive --region $REGION
        aws s3 rb "s3://$bucket_name" --force --region $REGION
        echo "   Bucket eliminato"
    else
        echo "   Bucket non trovato"
    fi
    
    # 4. Elimina lo stack CloudFormation
    echo " - Eliminazione stack CloudFormation..."
    aws cloudformation delete-stack --stack-name "$pipeline_name" --region $REGION 2>/dev/null || echo "   Stack non trovato o già in eliminazione"
    
    # 5. Attendi completamento eliminazione
    echo " - Attesa completamento eliminazione..."
    aws cloudformation wait stack-delete-complete --stack-name "$pipeline_name" --region $REGION 2>/dev/null || echo "   Eliminazione completata o timeout"
    
    echo "Pipeline $pipeline_name eliminata completamente"
}

# Crea nuova pipeline
create_new_pipeline() {
    local new_version=$1
    local new_pipeline_name="$PIPELINE_BASE_NAME-$new_version"
    
    echo "Creazione nuova pipeline: $new_pipeline_name"
    
    # Parametri per il deploy (assumendo che siano disponibili)
    source ./pipeline-config.sh
    
    # Deploy dello stack CloudFormation
    aws cloudformation deploy \
        --template-file pipeline-template.yaml \
        --stack-name "$new_pipeline_name" \
        --parameter-overrides \
            GitHubOwner="$GITHUB_OWNER" \
            GitHubRepo="$GITHUB_REPO" \
            GitHubBranch="$GITHUB_BRANCH" \
            GitHubToken="$GITHUB_TOKEN" \
            EBApplicationName="$APP_NAME" \
            EBEnvironmentName="$ENV_NAME" \
            LambdaStackName="$LAMBDA_STACK" \
            PipelineVersion="$new_version" \
        --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
        --region $REGION
    
    echo "Pipeline $new_pipeline_name creata con successo"
    echo "URL Console: https://$REGION.console.aws.amazon.com/codesuite/codepipeline/pipelines/$new_pipeline_name/view"
}

# Main execution
main() {
    case "${1:-create}" in
        "delete")
            echo "Modalità: ELIMINAZIONE"
            existing_pipeline=$(find_existing_pipeline)
            delete_existing_pipeline "$existing_pipeline"
            ;;
        "recreate")
            echo "Modalità: RICREAZIONE"
            existing_pipeline=$(find_existing_pipeline)
            delete_existing_pipeline "$existing_pipeline"
            sleep 10
            new_version=$(get_next_pipeline_version)
            create_new_pipeline "$new_version"
            ;;
        "status")
            echo "Modalità: STATO"
            existing_pipeline=$(find_existing_pipeline)
            if [ -n "$existing_pipeline" ]; then
                echo "Pipeline attiva: $existing_pipeline"
                echo "Stato: $(aws cloudformation describe-stacks --stack-name "$existing_pipeline" --region $REGION --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND")"
            else
                echo "Nessuna pipeline attiva trovata"
            fi
            ;;
        "create"|*)
            echo "Modalità: CREAZIONE"
            existing_pipeline=$(find_existing_pipeline)
            if [ -n "$existing_pipeline" ]; then
                echo "Pipeline esistente trovata: $existing_pipeline"
                read -p "Vuoi ricrearla? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    delete_existing_pipeline "$existing_pipeline"
                    sleep 10
                else
                    echo "Mantenimento pipeline esistente"
                    exit 0
                fi
            fi
            new_version=$(get_next_pipeline_version)
            create_new_pipeline "$new_version"
            ;;
    esac
}

main "$@"