# Film Recommender System

Sistema di raccomandazione film deployato su AWS con architettura serverless e containerizzata.

## Architettura

- **Frontend**: Applicazione Flask containerizzata su Elastic Beanstalk
- **Backend**: API Gateway + Lambda Functions (Python 3.9)
- **Database**: DynamoDB per storage analytics
- **Autenticazione**: AWS Cognito User Pool
- **Code**: SQS per elaborazioni asincrone
- **CI/CD**: CodePipeline con GitHub integration

## Struttura Progetto

```
.
├── application.py          # Applicazione Flask (Frontend/Proxy)
├── Dockerfile              # Definizione ambiente container per Flask
├── buildspec.yml           # Istruzioni Build per AWS CodeBuild 
├── 1-cleanup-everything.sh # Script pulizia totale ambiente
├── 2-setup-infrastructure.sh # Script setup infrastruttura Cloud
├── 3-deploy-ecr-and-docker.sh # Script build/push Docker in ECR
├── 4-deploy-eb.sh          # Script deployment su Elastic Beanstalk
├── 5-create-pipeline.sh    # Script creazione pipeline CI/CD
├── deploy-complete.sh      # Script deployment completo automatizzato
├── pipeline-template.yaml  # Template CloudFormation per la pipeline
├── dockerrun.aws.json      # Manifest per deployment Docker su EB
├── requirements.txt        # Dipendenze Python per Flask/Proxy
├── template.yaml           # Definizione Serverless (SAM/API Gateway/SQS/DB)
├── lambda
│   └── src
│       ├── lambda_function.py    # Codice Lambda Controller/Dispatcher
│       └── queue_processor.py    # Codice Lambda Worker/Elaboratore 
└── static
    ├── html/
    │   ├── app.html            # Pagina Raccomandazioni (Area autenticata)
    │   └── index.html          # Pagina Login/Registrazione (Punto di ingresso)
    └── js/
        ├── app.js              # Logica Polling e Inoltro Asincrono
        └── auth.js             # Logica Autenticazione Cognito (Lato Client)
```

## Deployment

### Opzione 1: Deploy Completo Automatico
```bash
export GITHUB_TOKEN="tuo-token-github"
./deploy-complete.sh
```

### Opzione 2: Deploy Manuale Passo-Passo
```bash
# 1. Infrastruttura base (Lambda, API Gateway, Cognito)
./2-setup-infrastructure.sh

# 2. Build e push immagine Docker
./3-deploy-ecr-and-docker.sh

# 3. Deploy su Elastic Beanstalk
./4-deploy-eb.sh

# 4. (Opzionale) Creazione pipeline CI/CD
./5-create-pipeline.sh
```

## Credenziali Test

- **URL Applicazione**: Controlla output dello script di deploy
- **Email**: test@filmrecommender.com
- **Password**: Password123!

## API Endpoints

- `POST /api/recommend` - Raccomandazioni sincrone
- `POST /api/recommend/async` - Raccomandazioni asincrone (SQS)
- `GET /api/recommend/status/{id}` - Stato richiesta asincrona
- `GET /api/analytics` - Metriche utilizzo
- `GET /api/health` - Health check

## Troubleshooting

### Problema: "Errore di connessione al servizio di coda"
Verifica che `application.py` abbia l'URL API Gateway corretto:
```bash
cat application.py | grep "API_GATEWAY_URL"
```

### Problema: Pipeline CI/CD fallisce
1. Prima fai commit dei file corretti su GitHub
2. Poi crea la pipeline CI/CD

## Note Importanti

- Il progetto utilizza AWS Free Tier
- Monitorare l'utilizzo per evitare costi non previsti
- I file di configurazione vengono aggiornati automaticamente dagli script
- La pipeline CI/CD si attiva automaticamente ad ogni push su GitHub

## File Chiave

- `template.yaml`: Definisce tutta l'infrastruttura AWS
- `application.py`: Logica applicazione Flask
- `static/js/auth.js`: Gestione autenticazione Cognito
- `static/js/app.js`: Logica frontend
- `buildspec.yml`: Configurazione build pipeline CI/CD