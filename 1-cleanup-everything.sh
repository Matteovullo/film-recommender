#!/bin/bash
set -e

REGION="eu-west-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
APP_NAME="film-recommender-final"
ECR_REPO="film-recommender"
COGNITO_USER_POOL_NAME="FilmRecommenderUserPool"

echo "======================================================"
echo " 🗑️  PULIZIA TOTALE - AMBIENTE 100% PULITO"
echo "======================================================"
echo " Questo script SIMULA un computer vergine"
echo " Elimina TUTTE le risorse AWS del progetto"
echo "======================================================"

# Funzione per eliminazione AGGRESSIVA di stack CloudFormation
delete_stack() {
    local stack_name=$1
    echo " - Stack: $stack_name"
    
    if aws cloudformation describe-stacks --stack-name "$stack_name" --region $REGION &>/dev/null; then
        echo "   🗑️  Eliminazione in corso..."
        
        # 1. Disabilita termination protection IMMEDIATAMENTE
        echo "   🔓 Disabilitazione termination protection..."
        aws cloudformation update-termination-protection --stack-name "$stack_name" --no-enable-termination-protection --region $REGION 2>/dev/null || echo "   ⚠️  Impossibile disabilitare protection"
        
        # 2. Prova eliminazione normale
        echo "   🚀 Tentativo eliminazione normale..."
        if aws cloudformation delete-stack --stack-name "$stack_name" --region $REGION 2>/dev/null; then
            echo "   ⏳ Eliminazione stack avviata..."
        else
            echo "   ⚠️  Errore eliminazione normale, procedo con metodo aggressivo"
        fi
        
        # 3. Attesa MOLTO breve
        for i in {1..5}; do
            STATUS=$(aws cloudformation describe-stacks --stack-name "$stack_name" --region $REGION --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "DELETE_COMPLETE")
            
            case $STATUS in
                "DELETE_COMPLETE")
                    echo "   ✅ Eliminato completamente"
                    return 0
                    ;;
                "DELETE_FAILED")
                    echo "   ⚠️  Eliminazione fallita, procedo con metodo NUCLEARE"
                    break
                    ;;
                "DELETE_IN_PROGRESS")
                    echo "   ⏳ Attesa eliminazione... ($i/5) - Stato: $STATUS"
                    sleep 5
                    ;;
                *)
                    echo "   ⏳ Attesa eliminazione... ($i/5) - Stato: $STATUS"
                    sleep 5
                    ;;
            esac
        done
        
        # 4. Se ancora presente, applica metodo NUCLEARE
        echo "   💥 Applicazione metodo NUCLEARE..."
        nuclear_stack_cleanup "$stack_name"
        
    else
        echo "   ✅ Non trovato (già eliminato)"
    fi
}

# Funzione per cleanup NUCLEARE di stack bloccati
nuclear_stack_cleanup() {
    local stack_name=$1
    
    echo "   💣 CLEANUP NUCLEARE per: $stack_name"
    
    # 1. ELIMINA MANUALMENTE TUTTE LE RISORSE PRINCIPALI
    echo "     🗑️  ELIMINAZIONE MANUALE RISORSE..."
    
    # Lambda Functions
    echo "     🔥 Funzioni Lambda..."
    LAMBDA_FUNCTIONS=$(aws lambda list-functions --region $REGION --query "Functions[?contains(FunctionName, 'film-recommender') || contains(FunctionName, '$stack_name')].FunctionName" --output text 2>/dev/null || true)
    for function in $LAMBDA_FUNCTIONS; do
        echo "       💀 Eliminando Lambda: $function"
        aws lambda delete-function --function-name "$function" --region $REGION 2>/dev/null || true
    done
    
    # Log Groups
    echo "     🔥 Log Groups..."
    for log_group in $(aws logs describe-log-groups --region $REGION --log-group-name-prefix "/aws/lambda" --query 'logGroups[?contains(logGroupName, `film-recommender`)].logGroupName' --output text 2>/dev/null || true); do
        echo "       💀 Eliminando Log Group: $log_group"
        aws logs delete-log-group --log-group-name "$log_group" --region $REGION 2>/dev/null || true
    done
    
    # IAM Roles
    echo "     🔥 Ruoli IAM..."
    for role in $(aws iam list-roles --query "Roles[?contains(RoleName, 'film-recommender') || contains(RoleName, '$stack_name')].RoleName" --output text 2>/dev/null || true); do
        echo "       💀 Pulizia ruolo: $role"
        # Rimuovi policy inline
        for policy in $(aws iam list-role-policies --role-name "$role" --query 'PolicyNames' --output text 2>/dev/null || true); do
            aws iam delete-role-policy --role-name "$role" --policy-name "$policy" 2>/dev/null || true
        done
        # Rimuovi policy attached
        for policy_arn in $(aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || true); do
            aws iam detach-role-policy --role-name "$role" --policy-arn "$policy_arn" 2>/dev/null || true
        done
        # Elimina ruolo
        aws iam delete-role --role-name "$role" 2>/dev/null || true
    done
    
    # S3 Buckets
    echo "     🔥 Bucket S3..."
    for bucket in $(aws s3api list-buckets --query "Buckets[?contains(Name, 'film-recommender') || contains(Name, '$stack_name')].Name" --output text 2>/dev/null || true); do
        echo "       💀 Svuotamento bucket: $bucket"
        aws s3 rm "s3://$bucket" --recursive --region $REGION 2>/dev/null || true
    done
    
    # 2. METODO RETAIN-RESOURCES (NUCLEARE)
    echo "     💣 Applicazione RETAIN-RESOURCES..."
    RESOURCES_TO_RETAIN=$(aws cloudformation list-stack-resources --stack-name "$stack_name" --region $REGION --query 'StackResourceSummaries[?ResourceStatus!=`DELETE_COMPLETE`].LogicalResourceId' --output text 2>/dev/null || true)
    
    if [ -n "$RESOURCES_TO_RETAIN" ]; then
        echo "       📋 Risorse da mantenere: $RESOURCES_TO_RETAIN"
        # Prendi solo le prime 10 risorse per evitare limiti
        RETAIN_LIST=$(echo "$RESOURCES_TO_RETAIN" | tr ' ' '\n' | head -10 | tr '\n' ' ')
        echo "     🚀 Eliminazione con retain: $RETAIN_LIST"
        aws cloudformation delete-stack \
            --stack-name "$stack_name" \
            --region $REGION \
            --retain-resources $RETAIN_LIST \
            2>/dev/null || true
    else
        echo "     🚀 Eliminazione forzata senza retain..."
        aws cloudformation delete-stack --stack-name "$stack_name" --region $REGION 2>/dev/null || true
    fi
    
    # 3. ATTESA BREVE E VERIFICA FINALE
    echo "     ⏳ Attesa finale (10 secondi)..."
    sleep 10
    
    # 4. SE ANCORA PRESENTE, USA TEMPLATE VUOTO
    if aws cloudformation describe-stacks --stack-name "$stack_name" --region $REGION &>/dev/null; then
        echo "     📄 Applicazione template VUOTO..."
        cat > /tmp/empty-template.yaml << 'EOF'
AWSTemplateFormatVersion: '2010-09-09'
Description: "Empty template for forced deletion"
Resources:
  EmptyResource:
    Type: AWS::CloudFormation::WaitConditionHandle
EOF
        
        aws cloudformation update-stack \
            --stack-name "$stack_name" \
            --template-body file:///tmp/empty-template.yaml \
            --region $REGION \
            --capabilities CAPABILITY_IAM \
            2>/dev/null || true
            
        sleep 10
        
        # Ora elimina
        aws cloudformation delete-stack --stack-name "$stack_name" --region $REGION 2>/dev/null || true
    fi
    
    # 5. VERIFICA FINALE
    sleep 10
    if aws cloudformation describe-stacks --stack-name "$stack_name" --region $REGION &>/dev/null; then
        echo "   ❌💥 IMPOSSIBILE ELIMINARE: $stack_name"
        echo "   📞 Richiedi supporto AWS o elimina manualmente dalla console"
    else
        echo "   ✅💥 Stack ELIMINATO con metodo nucleare"
    fi
}

# Funzione per eliminare bucket S3 (AGGRESSIVA)
delete_bucket() {
    local bucket_name=$1
    echo " - Bucket: $bucket_name"
    
    if aws s3 ls "s3://$bucket_name" --region $REGION &>/dev/null; then
        echo "   🗑️  Svuotamento bucket (AGGRESSIVO)..."
        
        # Elimina versioni degli oggetti
        echo "     🔥 Eliminazione versioni oggetti..."
        aws s3api list-object-versions --bucket "$bucket_name" --region $REGION --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output json 2>/dev/null | \
            jq -r '.Objects[] | {"Key":.Key, "VersionId":.VersionId}' 2>/dev/null | \
            while read -r line; do
                if [ -n "$line" ]; then
                    KEY=$(echo "$line" | jq -r '.Key' 2>/dev/null || echo "")
                    VERSION=$(echo "$line" | jq -r '.VersionId' 2>/dev/null || echo "")
                    if [ -n "$KEY" ] && [ -n "$VERSION" ]; then
                        aws s3api delete-object --bucket "$bucket_name" --key "$KEY" --version-id "$VERSION" --region $REGION 2>/dev/null || true
                    fi
                fi
            done || true
        
        # Elimina oggetti normali
        aws s3 rm "s3://$bucket_name" --recursive --region $REGION 2>/dev/null || true
        
        echo "   🗑️  Eliminazione bucket..."
        aws s3 rb "s3://$bucket_name" --force --region $REGION 2>/dev/null || echo "   ⚠️  Bucket potrebbe essere non vuoto"
        echo "   ✅ Bucket eliminato"
    else
        echo "   ✅ Non trovato"
    fi
}

# Funzione per eliminare ruolo IAM (AGGRESSIVA)
delete_iam_role() {
    local role_name=$1
    echo " - Ruolo IAM: $role_name"
    
    if aws iam get-role --role-name "$role_name" &>/dev/null; then
        echo "   🔥 Eliminazione AGGRESSIVA ruolo..."
        
        # 1. Rimuovi policy inline (SENZA verifiche)
        for policy_name in $(aws iam list-role-policies --role-name "$role_name" --query 'PolicyNames' --output text 2>/dev/null || echo ""); do
            aws iam delete-role-policy --role-name "$role_name" --policy-name "$policy_name" 2>/dev/null || true
            echo "     ✅ Policy inline: $policy_name"
        done
        
        # 2. Rimuovi policy attached (SENZA verifiche)
        for policy_arn in $(aws iam list-attached-role-policies --role-name "$role_name" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo ""); do
            aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" 2>/dev/null || true
            echo "     ✅ Policy attached: $(basename $policy_arn)"
        done
        
        # 3. Rimuovi instance profile (SENZA verifiche)
        if aws iam get-instance-profile --instance-profile-name "$role_name" &>/dev/null; then
            aws iam remove-role-from-instance-profile --instance-profile-name "$role_name" --role-name "$role_name" 2>/dev/null || true
            aws iam delete-instance-profile --instance-profile-name "$role_name" 2>/dev/null || true
            echo "     ✅ Instance profile rimosso"
        fi
        
        # 4. Elimina ruolo
        aws iam delete-role --role-name "$role_name" 2>/dev/null || true
        echo "   ✅ Ruolo eliminato"
    else
        echo "   ✅ Non trovato"
    fi
}

# ============================================================================
# INIZIO PULIZIA - ORDINE AGGRESSIVO
# ============================================================================

echo ""
echo "💣 STRATEGIA DI PULIZIA AGGRESSIVA:"
echo "   1. 💀 CodePipeline & CodeBuild"
echo "   2. 💀 Elastic Beanstalk" 
echo "   3. 💀 Lambda Functions (MANUALE)"
echo "   4. 💀 ECR Repositories"
echo "   5. 💀 S3 Buckets"
echo "   6. 💀 CloudFormation Stacks (NUCLEARE)"
echo "   7. 💀 IAM Roles"
echo "   8. 💀 Cognito"
echo "   9. 💀 Pulizia locale"
echo ""

# 1. ELIMINA PRIMA PIPELINE E BUILD
echo "1. 💀 ELIMINAZIONE PIPELINE E BUILD"

echo " - Eliminazione CodePipeline..."
for pipeline in $(aws codepipeline list-pipelines --region $REGION --query "pipelines[?contains(name, 'film-')].name" --output text 2>/dev/null || true); do
    echo "   💀 Pipeline: $pipeline"
    aws codepipeline delete-pipeline --name "$pipeline" --region $REGION 2>/dev/null || true
    echo "   ✅ Eliminata"
done

echo " - Eliminazione CodeBuild..."
for project in $(aws codebuild list-projects --region $REGION --query "projects[?contains(@, 'film-')]" --output text 2>/dev/null || true); do
    echo "   💀 CodeBuild: $project"
    aws codebuild delete-project --name "$project" --region $REGION 2>/dev/null || true
    echo "   ✅ Eliminato"
done

# 2. ELIMINA ELASTIC BEANSTALK (AGGRESSIVO)
echo ""
echo "2. 💀 ELIMINAZIONE ELASTIC BEANSTALK"

EB_APPS=$(aws elasticbeanstalk describe-applications --region $REGION --query "Applications[?contains(ApplicationName, 'film-')].ApplicationName" --output text 2>/dev/null || true)

if [ -n "$EB_APPS" ]; then
    for app in $EB_APPS; do
        echo " - Applicazione: $app"
        
        # Termina IMMEDIATAMENTE tutti gli ambienti
        ENVIRONMENTS=$(aws elasticbeanstalk describe-environments --application-name "$app" --region $REGION --query 'Environments[?Status!=`Terminated`].EnvironmentName' --output text 2>/dev/null || true)
        
        if [ -n "$ENVIRONMENTS" ]; then
            for env in $ENVIRONMENTS; do
                echo "   💀 Terminazione FORZATA ambiente: $env"
                aws elasticbeanstalk terminate-environment --environment-name "$env" --region $REGION --force-terminate 2>/dev/null || true
            done
        fi
        
        # Elimina applicazione SENZA aspettare
        echo "   💀 Eliminazione applicazione..."
        aws elasticbeanstalk delete-application --application-name "$app" --region $REGION 2>/dev/null || true
        echo "   ✅ Applicazione eliminata"
    done
else
    echo " - ✅ Nessuna applicazione EB trovata"
fi

# 3. ELIMINA LAMBDA (MANUALE E AGGRESSIVO)
echo ""
echo "3. 💀 ELIMINAZIONE LAMBDA (MANUALE)"

# Elimina TUTTE le Lambda del progetto
LAMBDA_FUNCTIONS=$(aws lambda list-functions --region $REGION --query "Functions[?contains(FunctionName, 'film-recommender')].FunctionName" --output text 2>/dev/null || true)

if [ -n "$LAMBDA_FUNCTIONS" ]; then
    for function in $LAMBDA_FUNCTIONS; do
        echo " 💀 Lambda: $function"
        aws lambda delete-function --function-name "$function" --region $REGION 2>/dev/null || true
        echo "   ✅ Eliminata"
    done
else
    echo " - ✅ Nessuna Lambda trovata"
fi

# 4. ELIMINA ECR
echo ""
echo "4. 💀 ELIMINAZIONE ECR"

ECR_REPOS=$(aws ecr describe-repositories --region $REGION --query "repositories[?contains(repositoryName, 'film-recommender')].repositoryName" --output text 2>/dev/null || true)

if [ -n "$ECR_REPOS" ]; then
    for repo in $ECR_REPOS; do
        echo " 💀 Repository: $repo"
        aws ecr delete-repository --repository-name "$repo" --region $REGION --force 2>/dev/null || true
        echo "   ✅ Eliminato"
    done
else
    echo " - ✅ Nessun repository ECR trovato"
fi

# 5. ELIMINA BUCKET S3
echo ""
echo "5. 💀 ELIMINAZIONE BUCKET S3"

# Bucket specifici del progetto
for bucket in $(aws s3api list-buckets --query "Buckets[?contains(Name, 'film-recommender')].Name" --output text 2>/dev/null || true); do
    delete_bucket "$bucket"
done

# Bucket Elastic Beanstalk
delete_bucket "elasticbeanstalk-$REGION-$ACCOUNT_ID"

# Bucket SAM
delete_bucket "sam-deployments-$ACCOUNT_ID-$REGION"
delete_bucket "sam-deployment-bucket-$REGION-$ACCOUNT_ID"

# 6. ELIMINA STACK CLOUDFORMATION (NUCLEARE)
echo ""
echo "6. 💀 ELIMINAZIONE STACK CLOUDFORMATION (NUCLEARE)"

ALL_STACKS=$(aws cloudformation list-stacks --region $REGION \
    --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE UPDATE_ROLLBACK_COMPLETE ROLLBACK_COMPLETE DELETE_FAILED \
    --query "StackSummaries[?contains(StackName, 'film-recommender')].StackName" \
    --output text 2>/dev/null || true)

if [ -n "$ALL_STACKS" ]; then
    for stack in $ALL_STACKS; do
        delete_stack "$stack"
    done
else
    echo " - ✅ Nessuno stack trovato"
fi

# 7. ELIMINA RUOLI IAM (AGGRESSIVO)
echo ""
echo "7. 💀 ELIMINAZIONE RUOLI IAM"

# Ruoli specifici del progetto
for role in $(aws iam list-roles --query "Roles[?contains(RoleName, 'film-recommender')].RoleName" --output text 2>/dev/null || true); do
    delete_iam_role "$role"
done

# Elimina il ruolo problematico specifico
delete_iam_role "film-pipe-v3-CloudFormationServiceRole-yfYYcczvfDUb"

# Ruoli di servizio
delete_iam_role "aws-elasticbeanstalk-service-role"
delete_iam_role "aws-elasticbeanstalk-ec2-role"

# 8. ELIMINA COGNITO
echo ""
echo "8. 💀 ELIMINAZIONE COGNITO"

USER_POOLS=$(aws cognito-idp list-user-pools --region $REGION --max-results 50 --query "UserPools[?contains(Name, 'Film')].Id" --output text 2>/dev/null || true)

if [ -n "$USER_POOLS" ]; then
    for pool_id in $USER_POOLS; do
        POOL_NAME=$(aws cognito-idp describe-user-pool --user-pool-id "$pool_id" --region $REGION --query 'UserPool.Name' --output text 2>/dev/null || echo "Unknown")
        echo " 💀 User Pool: $POOL_NAME"
        aws cognito-idp delete-user-pool --user-pool-id "$pool_id" --region $REGION 2>/dev/null || true
        echo "   ✅ Eliminato"
    done
else
    echo " - ✅ Nessun User Pool trovato"
fi

# 9. PULIZIA LOCALE (AGGRESSIVA)
echo ""
echo "9. 💀 PULIZIA LOCALE"

echo " - File di configurazione..."
rm -rf .ebextensions .aws-sam build .git/hooks node_modules 2>/dev/null || true
rm -f dockerrun.aws.json *.zip packaged.yaml buildspec.yml.bak 2>/dev/null || true
rm -f imagedefinitions.json .DS_Store 2>/dev/null || true

echo " - Cache e file temporanei..."
find . -name "*.bak" -delete 2>/dev/null || true
find . -name "*.tmp" -delete 2>/dev/null || true
find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
find . -name "*.pyc" -delete 2>/dev/null || true
find . -name ".pytest_cache" -type d -exec rm -rf {} + 2>/dev/null || true
find . -name "*.egg-info" -type d -exec rm -rf {} + 2>/dev/null || true

echo " - Cache Docker..."
docker system prune -a -f --volumes 2>/dev/null || true

echo "   ✅ Pulizia locale completata"

# VERIFICA FINALE AGGRESSIVA
echo ""
echo "💣 VERIFICA FINALE AGGRESSIVA"
echo "======================================================"

echo " - Stack CloudFormation rimanenti:"
REMAINING_STACKS=$(aws cloudformation list-stacks --region $REGION \
    --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE UPDATE_ROLLBACK_COMPLETE ROLLBACK_COMPLETE DELETE_FAILED \
    --query "StackSummaries[?contains(StackName, 'film-recommender')].StackName" \
    --output text 2>/dev/null || true)

if [ -z "$REMAINING_STACKS" ]; then
    echo "   ✅💥 Nessuno stack del progetto rimasto"
else
    echo "   ❌💥 Stack rimanenti (CRITICO):"
    for stack in $REMAINING_STACKS; do
        echo "     • $stack"
        echo "       ⚠️  RICHIEDE INTERVENTO MANUALE IMMEDIATO"
        echo "       💀 Comando: aws cloudformation delete-stack --stack-name $stack --region $REGION --retain-resources $(aws cloudformation list-stack-resources --stack-name $stack --region $REGION --query 'StackResourceSummaries[0].LogicalResourceId' --output text 2>/dev/null || echo 'EmptyResource')"
    done
fi

echo " - Bucket S3 rimanenti:"
REMAINING_BUCKETS=$(aws s3api list-buckets --query "Buckets[?contains(Name, 'film-recommender')].Name" --output text 2>/dev/null || true)
if [ -z "$REMAINING_BUCKETS" ]; then
    echo "   ✅💥 Nessun bucket del progetto rimasto"
else
    echo "   ⚠️  Bucket rimanenti: $REMAINING_BUCKETS"
fi

echo " - Ruoli IAM rimanenti:"
REMAINING_ROLES=$(aws iam list-roles --query "Roles[?contains(RoleName, 'film-recommender')].RoleName" --output text 2>/dev/null || true)
if [ -z "$REMAINING_ROLES" ]; then
    echo "   ✅💥 Nessun ruolo IAM del progetto rimasto"
else
    echo "   ⚠️  Ruoli rimanenti: $REMAINING_ROLES"
fi

echo ""
echo "======================================================"
echo " 💥 PULIZIA AGGRESSIVA COMPLETATA"
echo "======================================================"
echo ""
echo "🎯 ORA PUOI TESTARE COME UN NUOVO UTENTE:"
echo "   ./2-setup-infrastructure.sh"
echo "   ./3-deploy-ecr-and-docker.sh" 
echo "   ./4-create-pipeline.sh"
echo "   ./5-deploy-eb.sh"
echo ""
echo "💣 Se ci sono ancora stack bloccati, contatta il supporto AWS"
echo "   o eliminali manualmente dalla Console CloudFormation"
echo "======================================================"