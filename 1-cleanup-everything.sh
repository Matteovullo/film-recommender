#!/bin/bash
set -e

REGION="eu-west-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
APP_NAME="film-recommender-final"
ECR_REPO="film-recommender"
COGNITO_USER_POOL_NAME="FilmRecommenderUserPool"

echo "======================================================"
echo " 🗑️  PULIZIA TOTALE - TUTTE LE RISORSE"
echo "======================================================"

# Funzione per eliminare stack CloudFormation
delete_stack() {
    local stack_name=$1
    echo " - Stack: $stack_name"
    if aws cloudformation describe-stacks --stack-name "$stack_name" --region $REGION &>/dev/null; then
        aws cloudformation delete-stack --stack-name "$stack_name" --region $REGION
        echo "   ⏳ Eliminazione in corso..."
        aws cloudformation wait stack-delete-complete --stack-name "$stack_name" --region $REGION 2>/dev/null || echo "   ✅ Completato (o già eliminato)"
    else
        echo "   ✅ Non trovato"
    fi
}

# Funzione per eliminare bucket S3
delete_bucket() {
    local bucket_name=$1
    echo " - Bucket: $bucket_name"
    if aws s3 ls "s3://$bucket_name" --region $REGION &>/dev/null; then
        echo "   Svuotamento bucket..."
        aws s3 rm "s3://$bucket_name" --recursive --region $REGION || true
        echo "   Eliminazione bucket..."
        aws s3 rb "s3://$bucket_name" --force --region $REGION || true
        echo "   ✅ Eliminato"
    else
        echo "   ✅ Non trovato"
    fi
}

# 1. ELIMINA PIPELINE E STACK CORRELATI
echo "1. ELIMINAZIONE PIPELINE E CI/CD"
pipeline_stacks=$(aws cloudformation list-stacks --region $REGION --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --query "StackSummaries[?contains(StackName, 'film-recommender-pipeline')].StackName" --output text 2>/dev/null || true)

if [ -n "$pipeline_stacks" ]; then
    for stack in $pipeline_stacks; do
        delete_stack "$stack"
    done
else
    echo " - Nessuno stack pipeline trovato"
fi

# Elimina bucket pipeline
echo " - Pulizia bucket pipeline..."
for bucket in film-recommender-pipeline-v7 film-recommender-pipeline-v8 film-recommender-pipeline-v9 film-recommender-pipeline-v10 film-recommender-pipeline-v11 film-recommender-pipeline-v12; do
    delete_bucket "$bucket-$ACCOUNT_ID"
done

# Elimina risorse CodePipeline e CodeBuild direttamente
echo " - Pulizia risorse CodePipeline..."
for pipeline in film-recommender-pipeline-v7 film-recommender-pipeline-v8 film-recommender-pipeline-v9 film-recommender-pipeline-v10 film-recommender-pipeline-v11 film-recommender-pipeline-v12; do
    if aws codepipeline get-pipeline --name "$pipeline" --region $REGION &>/dev/null; then
        aws codepipeline delete-pipeline --name "$pipeline" --region $REGION
        echo "   CodePipeline $pipeline eliminata"
    fi
done

echo " - Pulizia risorse CodeBuild..."
for project in film-recommender-build-v7 film-recommender-build-v8 film-recommender-build-v9 film-recommender-build-v10 film-recommender-build-v11 film-recommender-build-v12; do
    if aws codebuild batch-get-projects --names "$project" --region $REGION --query "projects[0]" --output text &>/dev/null; then
        aws codebuild delete-project --name "$project" --region $REGION
        echo "   CodeBuild $project eliminato"
    fi
done

# 2. ELIMINA ELASTIC BEANSTALK (VERSIONE CORRETTA per AWS CLI v2)
echo "2. ELIMINAZIONE ELASTIC BEANSTALK"
if aws elasticbeanstalk describe-applications --application-name "$APP_NAME" --region $REGION &>/dev/null; then
    echo " - Applicazione: $APP_NAME"
    
    # Prima termina tutti gli ambienti
    ENVIRONMENTS=$(aws elasticbeanstalk describe-environments --application-name "$APP_NAME" --region $REGION --query 'Environments[?Status!=`Terminated`].EnvironmentName' --output text 2>/dev/null || true)
    
    if [ -n "$ENVIRONMENTS" ]; then
        for env in $ENVIRONMENTS; do
            echo "   Terminazione ambiente: $env"
            aws elasticbeanstalk terminate-environment --environment-name "$env" --region $REGION || true
        done
        
        # Attendi che tutti gli ambienti siano terminati
        for env in $ENVIRONMENTS; do
            echo "   Attesa terminazione ambiente: $env"
            aws elasticbeanstalk wait environment-terminated --environment-names "$env" --region $REGION 2>/dev/null || echo "   Ambiente $env terminato"
        done
    fi
    
    # Poi elimina l'applicazione
    echo "   Eliminazione applicazione..."
    aws elasticbeanstalk delete-application --application-name "$APP_NAME" --region $REGION
    echo "   ✅ Applicazione eliminata"
else
    echo " - Applicazione EB: ✅ Non trovata"
fi

# 3. ELIMINA STACK LAMBDA
echo "3. ELIMINAZIONE STACK LAMBDA"
delete_stack "$APP_NAME-lambda"

# 4. ELIMINA COGNITO
echo "4. ELIMINAZIONE COGNITO"
USER_POOL_ID=$(aws cognito-idp list-user-pools --region $REGION --max-results 20 --query "UserPools[?Name=='$COGNITO_USER_POOL_NAME'].Id" --output text 2>/dev/null || true)
if [ -n "$USER_POOL_ID" ]; then
    echo " - User Pool: $COGNITO_USER_POOL_NAME"
    aws cognito-idp delete-user-pool --user-pool-id "$USER_POOL_ID" --region $REGION
    echo "   ✅ Eliminato"
else
    echo " - User Pool: ✅ Non trovato"
fi

# 5. ELIMINA ECR
echo "5. ELIMINAZIONE ECR"
if aws ecr describe-repositories --repository-names "$ECR_REPO" --region $REGION &>/dev/null; then
    echo " - Repository ECR: $ECR_REPO"
    aws ecr delete-repository --repository-name "$ECR_REPO" --region $REGION --force
    echo "   ✅ Eliminato"
else
    echo " - Repository ECR: ✅ Non trovato"
fi

# 6. ELIMINA BUCKET S3
echo "6. ELIMINAZIONE BUCKET S3"
delete_bucket "elasticbeanstalk-$REGION-$ACCOUNT_ID"
delete_bucket "sam-deployment-bucket-$REGION-$ACCOUNT_ID"

# 7. PULIZIA RUOLI IAM
echo "7. PULIZIA RUOLI IAM"
remove_iam_role() {
    local role_name=$1
    echo " - Ruolo IAM: $role_name"
    
    if aws iam get-role --role-name "$role_name" &>/dev/null; then
        # Rimuovi policy inline
        for policy_name in $(aws iam list-role-policies --role-name "$role_name" --query 'PolicyNames' --output text 2>/dev/null || true); do
            aws iam delete-role-policy --role-name "$role_name" --policy-name "$policy_name" 2>/dev/null || true
        done
        
        # Rimuovi policy attached
        for policy_arn in $(aws iam list-attached-role-policies --role-name "$role_name" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || true); do
            aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" 2>/dev/null || true
        done
        
        # Rimuovi dall'instance profile se esiste
        if aws iam get-instance-profile --instance-profile-name "$role_name" &>/dev/null; then
            aws iam remove-role-from-instance-profile --instance-profile-name "$role_name" --role-name "$role_name" 2>/dev/null || true
            aws iam delete-instance-profile --instance-profile-name "$role_name" 2>/dev/null || true
        fi
        
        # Elimina il ruolo
        aws iam delete-role --role-name "$role_name" 2>/dev/null || true
        echo "   ✅ Eliminato"
    else
        echo "   ✅ Non trovato"
    fi
}

remove_iam_role "aws-elasticbeanstalk-service-role"
remove_iam_role "aws-elasticbeanstalk-ec2-role"
remove_iam_role "film-recommender-build-v7"
remove_iam_role "film-recommender-build-v8"
remove_iam_role "film-recommender-build-v9"
remove_iam_role "film-recommender-build-v10"

# 8. PULIZIA LOCALE
echo "8. PULIZIA FILE LOCALI"
rm -rf .ebextensions .aws-sam 2>/dev/null || true
rm -f dockerrun.aws.json *.zip 2>/dev/null || true
find . -name "*.bak" -delete 2>/dev/null || true
docker container prune -f 2>/dev/null || true
docker image prune -a -f 2>/dev/null || true
echo "   ✅ Pulizia completata"

echo "======================================================"
echo " ✅ PULIZIA TOTALE COMPLETATA"
echo "======================================================"
echo "Tutte le risorse AWS sono state eliminate"
echo "File locali puliti"
echo ""
echo "Pronto per un nuovo deploy!"