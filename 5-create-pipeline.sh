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
        --output text 2>/dev/null || echo "")
    
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
    echo "   2. Clicca 'Generate new token' (classic)"
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
    
    # Verifica base del token (dovrebbe iniziare con ghp_)
    if [[ ! $GITHUB_TOKEN =~ ^(ghp_|github_pat_) ]]; then
        echo "⚠️  Il token non sembra nel formato standard"
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
        echo "   Creazione template di emergenza..."
        create_emergency_template
    else
        echo "✅ Template pipeline trovato"
    fi
}

# FUNZIONE: Crea template di emergenza
create_emergency_template() {
    cat > pipeline-template.yaml << 'EOF'
AWSTemplateFormatVersion: '2010-09-09'
Description: Film Recommender CICD Pipeline with GitHub integration

Parameters:
  GitHubOwner:
    Type: String
  GitHubRepo:
    Type: String  
    Default: film-recommender
  GitHubBranch:
    Type: String
    Default: main
  GitHubToken:
    Type: String
    NoEcho: true
  EBApplicationName:
    Type: String
    Description: Elastic Beanstalk application name
    Default: film-recommender-final
  EBEnvironmentName:
    Type: String
    Description: Elastic Beanstalk environment name
    Default: film-recommender-final-env
  LambdaStackName:
    Type: String
    Description: Lambda CloudFormation stack name
    Default: film-recommender-final-lambda-stack
  PipelineVersion:
    Type: String
    Description: Pipeline version identifier
    Default: v1

Resources:
  # S3 Bucket per artifacts
  ArtifactStoreBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Sub 'film-pipe-${PipelineVersion}-${AWS::AccountId}'
      VersioningConfiguration:
        Status: Enabled

  # CodeBuild Role con permessi completi
  CodeBuildRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: codebuild.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AdministratorAccess

  # CodeBuild Project
  CodeBuildProject:
    Type: AWS::CodeBuild::Project
    Properties:
      Name: !Sub 'film-build-${PipelineVersion}'
      Description: Build project for Film Recommender application
      Source:
        Type: CODEPIPELINE
        BuildSpec: buildspec.yml
      Environment:
        Type: LINUX_CONTAINER
        ComputeType: BUILD_GENERAL1_MEDIUM
        Image: aws/codebuild/amazonlinux2-x86_64-standard:4.0
        PrivilegedMode: true
        EnvironmentVariables:
          - Name: PIPELINE_VERSION
            Value: !Ref PipelineVersion
          - Name: LAMBDA_STACK_NAME
            Value: !Ref LambdaStackName
      Artifacts:
        Type: CODEPIPELINE
      ServiceRole: !Ref CodeBuildRole
      TimeoutInMinutes: 30

  # CodePipeline Role
  CodePipelineRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: codepipeline.amazonaws.com
            Action: sts:AssumeRole
      Policies:
        - PolicyName: PipelineAccess
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action:
                  - codebuild:*
                  - s3:*
                  - ecr:*
                  - cloudformation:*
                  - elasticbeanstalk:*
                  - iam:PassRole
                Resource: "*"

  # CodePipeline
  CodePipeline:
    Type: AWS::CodePipeline::Pipeline
    Properties:
      Name: !Sub 'film-pipe-${PipelineVersion}'
      RoleArn: !GetAtt CodePipelineRole.Arn
      ArtifactStore:
        Type: S3
        Location: !Ref ArtifactStoreBucket
      Stages:
        - Name: Source
          Actions:
            - Name: GitHub-Source
              ActionTypeId:
                Category: Source
                Owner: ThirdParty
                Version: 1
                Provider: GitHub
              Configuration:
                Owner: !Ref GitHubOwner
                Repo: !Ref GitHubRepo
                Branch: !Ref GitHubBranch
                OAuthToken: !Ref GitHubToken
                PollForSourceChanges: false
              OutputArtifacts:
                - Name: SourceArtifact
              RunOrder: 1
        - Name: Build
          Actions:
            - Name: Build-And-Package
              ActionTypeId:
                Category: Build
                Owner: AWS
                Version: 1
                Provider: CodeBuild
              Configuration:
                ProjectName: !Ref CodeBuildProject
              InputArtifacts:
                - Name: SourceArtifact
              OutputArtifacts:
                - Name: BuildArtifact
              RunOrder: 1
        - Name: Deploy
          Actions:
            - Name: Deploy-Lambda
              ActionTypeId:
                Category: Deploy
                Owner: AWS
                Provider: CloudFormation
                Version: 1
              InputArtifacts:
                - Name: BuildArtifact
              Configuration:
                StackName: !Ref LambdaStackName
                ActionMode: CREATE_UPDATE
                TemplatePath: BuildArtifact::packaged.yaml
                Capabilities: CAPABILITY_IAM,CAPABILITY_AUTO_EXPAND
              RunOrder: 1
            - Name: Deploy-Frontend
              ActionTypeId:
                Category: Deploy
                Owner: AWS
                Provider: ElasticBeanstalk
                Version: 1
              InputArtifacts:
                - Name: BuildArtifact
              Configuration:
                ApplicationName: !Ref EBApplicationName
                EnvironmentName: !Ref EBEnvironmentName
              RunOrder: 2

Outputs:
  PipelineUrl:
    Description: CodePipeline Console URL
    Value: !Sub 'https://${AWS::Region}.console.aws.amazon.com/codesuite/codepipeline/pipelines/film-pipe-${PipelineVersion}/view'
  BuildProjectName:
    Description: CodeBuild Project Name
    Value: !Ref CodeBuildProject
  ArtifactBucket:
    Description: S3 Artifact Bucket
    Value: !Ref ArtifactStoreBucket
EOF
    echo "✅ Template di emergenza creato"
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

# FUNZIONE: Verifica buildspec
verify_buildspec() {
    if [ ! -f "buildspec.yml" ]; then
        echo "⚠️  buildspec.yml non trovato, creazione versione base..."
        cat > buildspec.yml << 'EOF'
version: 0.2

phases:
  install:
    runtime-versions:
      python: 3.9
    commands:
      - echo "=== INSTALLAZIONE DEPENDENZE ==="
      - yum install -y jq git
      - pip install --upgrade aws-sam-cli boto3 docker

  pre_build:
    commands:
      - echo "=== CONFIGURAZIONE PRE-BUILD ==="
      - ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
      - S3_BUCKET="film-pipe-$PIPELINE_VERSION-$ACCOUNT_ID"
      - ECR_REPO="film-recommender"
      - ECR_URL="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$ECR_REPO"
      - echo "Login ECR..."
      - aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_URL

  build:
    commands:
      - echo "=== FASE BUILD ==="
      - echo "Build Docker image..."
      - docker build -t $ECR_REPO .
      - docker tag $ECR_REPO:latest $ECR_URL:latest
      - echo "SAM packaging..."
      - sam build
      - sam package --template-file template.yaml --output-template-file packaged.yaml --s3-bucket $S3_BUCKET --region $REGION

  post_build:
    commands:
      - echo "=== FASE POST-BUILD ==="
      - echo "Push Docker image..."
      - docker push $ECR_URL:latest
      - echo "Deploy SAM..."
      - sam deploy --template-file packaged.yaml --stack-name $LAMBDA_STACK_NAME --capabilities CAPABILITY_IAM --region $REGION --no-fail-on-empty-changeset

artifacts:
  files:
    - packaged.yaml
    - '**/*'
EOF
    else
        echo "✅ buildspec.yml trovato"
    fi
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
    echo "⏳ Attesa creazione pipeline (30s)..."
    sleep 30
    
    # Verifica che la pipeline esista
    if aws codepipeline get-pipeline --name "film-pipe-$PIPELINE_VERSION" --region $REGION &>/dev/null; then
        echo "✅ Pipeline creata con successo"
        
        # Verifica webhook GitHub
        echo "🔗 Verifica webhook GitHub..."
        echo "💡 Controlla manualmente: https://github.com/$GITHUB_OWNER/$GITHUB_REPO/settings/hooks"
        
        # Trigger prima esecuzione
        echo "🚀 Avvio prima esecuzione pipeline..."
        aws codepipeline start-pipeline-execution \
            --name "film-pipe-$PIPELINE_VERSION" \
            --region $REGION
            
        echo "✅ Prima esecuzione avviata"
    else
        echo "⚠️  Pipeline creata ma non immediatamente disponibile"
        echo "💡 Controlla tra qualche minuto nella console AWS"
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
    echo "   CloudFormation: https://$REGION.console.aws.amazon.com/cloudformation/home"
    echo ""
    echo "🔧 COMPONENTI CONFIGURATI:"
    echo "   ✅ CodePipeline con trigger GitHub"
    echo "   ✅ CodeBuild con permessi Administrator"
    echo "   ✅ S3 Artifact Store"
    echo "   ✅ Deploy automatico a Elastic Beanstalk"
    echo "   ✅ Deploy automatico Lambda/API Gateway"
    echo ""
    echo "🚀 PROSSIMI PASSI:"
    echo "   1. Verifica webhook GitHub: https://github.com/$GITHUB_OWNER/$GITHUB_REPO/settings/hooks"
    echo "   2. La pipeline si attiverà al prossimo commit su GitHub"
    echo "   3. Monitora lo stato nella console AWS"
    echo ""
    echo "⚡ COMANDI RAPIDI:"
    echo "   Trigger manuale: aws codepipeline start-pipeline-execution --name film-pipe-$PIPELINE_VERSION --region $REGION"
    echo "   Stato pipeline: aws codepipeline get-pipeline-state --name film-pipe-$PIPELINE_VERSION --region $REGION"
    echo "   Logs CodeBuild: aws codebuild list-builds-for-project --project-name film-build-$PIPELINE_VERSION --region $REGION"
    echo ""
    echo "📝 NOTE IMPORTANTI:"
    echo "   - Il primo deploy richiede 15-20 minuti"
    echo "   - Se GitHub non triggera, usa il comando manuale sopra"
    echo "   - Verifica che il webhook sia configurato su GitHub"
    echo "======================================================"
}

# FUNZIONE: Gestione errori
handle_error() {
    echo ""
    echo "❌ ERRORE durante la creazione della pipeline"
    echo ""
    echo "💡 TROUBLESHOOTING:"
    echo "   - Verifica che il GitHub Token sia valido"
    echo "   - Controlla che il repository GitHub esista: https://github.com/$GITHUB_OWNER/$GITHUB_REPO"
    echo "   - Verifica i permessi IAM dell'utente AWS"
    echo "   - Controlla che non ci siano pipeline con lo stesso nome"
    echo ""
    echo "🔧 COMANDI DI DEBUG:"
    echo "   aws cloudformation describe-stack-events --stack-name $PIPELINE_STACK_NAME --region $REGION | head -20"
    echo "   aws cloudformation describe-stacks --stack-name $PIPELINE_STACK_NAME --region $REGION"
    echo "   aws codepipeline list-pipelines --region $REGION"
    echo ""
    exit 1
}

# FUNZIONE PRINCIPALE
main() {
    # Imposta trap per gestione errori
    trap handle_error ERR
    
    check_prerequisites
    verify_template
    verify_buildspec
    get_github_token
    deploy_pipeline
    verify_pipeline
    show_info
}

# Esegui
main