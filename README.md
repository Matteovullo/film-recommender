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
film-recommender/
├── application.py              # Applicazione Flask principale
├── template.yaml              # Template SAM (Infrastructure as Code)
├── Dockerfile                 # Configurazione container
├── buildspec.yml              # Configurazione CodeBuild
├── requirements.txt           # Dipendenze Python
├── lambda/src/                # Funzioni Lambda
├── static/                    # Frontend (HTML, JS, CSS)
└── scripts/                   # Script di deployment
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