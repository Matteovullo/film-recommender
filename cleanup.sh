set -e

REGION="eu-west-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
if [ -z "$ACCOUNT_ID" ]; then
    echo "Errore: Impossibile recuperare l'ID Account AWS. Verifica le tue credenziali."
    exit 1
fi

APP_NAME="film-recommender-final"
LAMBDA_STACK="$APP_NAME-lambda"
ENV_NAME="$APP_NAME-env"
ECR_REPO="film-recommender"
COGNITO_USER_POOL_NAME="FilmRecommenderUserPool"
S3_BUCKET_EB="elasticbeanstalk-$REGION-$ACCOUNT_ID"
S3_BUCKET_SAM="sam-deployment-bucket-$REGION-$ACCOUNT_ID" 

echo "======================================================"
echo "FASE DI PULIZIA TOTALE: ELIMINAZIONE INFRASTRUTTURA"
echo "   Regione: $REGION"
echo "   Account: $ACCOUNT_ID"
echo "======================================================"
sleep 3 

echo "1. Terminazione dell'ambiente Elastic Beanstalk ($ENV_NAME)..."
if aws elasticbeanstalk describe-environments --application-name $APP_NAME --environment-names "$ENV_NAME" --region $REGION --query 'Environments[0].Status' --output text 2>/dev/null | grep -q "Ready\|Updating\|Launching"; then
    aws elasticbeanstalk terminate-environment --environment-name "$ENV_NAME" --region $REGION
    echo "   Richiesta di terminazione inviata. Attendere il completamento..."
    aws elasticbeanstalk wait environment-terminated --environment-names "$ENV_NAME" --region $REGION || echo "   Ambiente terminato (o non esistente/già in fase di terminazione)."
else
    echo "   Ambiente EB non attivo o in stato Terminated, ignoro la terminazione."
fi

echo "   Eliminazione dell'applicazione Elastic Beanstalk ($APP_NAME)..."
aws elasticbeanstalk delete-application --application-name $APP_NAME --terminate-environments 2>/dev/null || echo "   Applicazione EB non trovata o già eliminata."

echo "2. Eliminazione dello Stack SAM/CloudFormation ($LAMBDA_STACK)..."
aws cloudformation delete-stack --stack-name $LAMBDA_STACK --region $REGION 2>/dev/null || echo "   Stack CloudFormation non trovato."

echo "3. Eliminazione User Pool Cognito ($COGNITO_USER_POOL_NAME)..."
USER_POOL_ID=$(aws cognito-idp list-user-pools --region $REGION --max-results 10 --query "UserPools[?Name=='$COGNITO_USER_POOL_NAME'].Id" --output text | head -1)
if [ -n "$USER_POOL_ID" ]; then
    aws cognito-idp delete-user-pool --user-pool-id $USER_POOL_ID --region $REGION
    echo "   User Pool Cognito eliminato: $USER_POOL_ID"
else
    echo "   User Pool Cognito non trovato, ignoro l'eliminazione."
fi

echo "4. Eliminazione Repository ECR ($ECR_REPO)..."
aws ecr delete-repository --repository-name $ECR_REPO --region $REGION --force 2>/dev/null || echo "   Repository ECR non trovato."

echo "5. Pulizia Bucket S3 SAM ($S3_BUCKET_SAM)..."
if aws s3 ls "s3://$S3_BUCKET_SAM" --region $REGION 2>/dev/null; then
    aws s3 rm s3://$S3_BUCKET_SAM --recursive
    aws s3 rb s3://$S3_BUCKET_SAM --force
    echo "   Bucket SAM svuotato ed eliminato."
else
    echo "   Bucket SAM non trovato, ignoro."
fi

echo "6. Pulizia Ruoli e Profili IAM..."

echo "   Attendo 10 secondi per la propagazione CloudFormation..."
sleep 10

remove_iam_role() {
    ROLE_NAME=$1
    echo "   Rimuovendo le policy dal ruolo $ROLE_NAME..."
    for policy_arn in $(aws iam list-attached-role-policies --role-name $ROLE_NAME --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null); do
        aws iam detach-role-policy --role-name $ROLE_NAME --policy-arn $policy_arn
    done
    
    echo "   Eliminando il ruolo $ROLE_NAME..."
    aws iam delete-role --role-name $ROLE_NAME 2>/dev/null || echo "   Ruolo $ROLE_NAME non trovato."
}

remove_iam_role "aws-elasticbeanstalk-service-role"

if aws iam get-instance-profile --instance-profile-name aws-elasticbeanstalk-ec2-role --region $REGION &>/dev/null; then
    aws iam remove-role-from-instance-profile --instance-profile-name aws-elasticbeanstalk-ec2-role --role-name aws-elasticbeanstalk-ec2-role
    aws iam delete-instance-profile --instance-profile-name aws-elasticbeanstalk-ec2-role
    echo "   Instance Profile EC2 eliminato."
fi
remove_iam_role "aws-elasticbeanstalk-ec2-role"

echo "======================================================"
echo "PULIZIA COMPLETATA CON SUCCESSO!"
echo "   Tutte le risorse create dal progetto sono state rimosse."
echo "======================================================"

echo "Esecuzione del reset locale dei file modificati..."

find static/js/ -name "*.bak" -delete 2>/dev/null || true
git checkout static/js/auth.js application.py static/js/app.js static/js/dashboard.js 2>/dev/null || echo "   Ignoro: File non tracciati da Git o modificati. Ripristina i placeholder manualmente se necessario."
rm -f dockerrun.aws.json $APP_NAME.zip

echo "Ambiente pronto per un nuovo re-deploy da zero!"
echo ""
echo "PROSSIMO PASSO: Esegui ./setup-cli.sh e poi ./deploy.sh"