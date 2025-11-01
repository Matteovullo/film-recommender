# Film Recommender su AWS

Film Recommender è una web app serverless su AWS per consigliare film in base alle preferenze utente, offrendo anche dashboard statistiche e gestione asincrona delle richieste.

---

## Descrizione del Progetto

- **Front-end:**  
  Sviluppato in HTML, CSS, JavaScript. Gli utenti inseriscono il genere preferito e ricevono raccomandazioni immediate. Sono presenti login, dashboard analytics e interfaccia responsive.

- **Back-end & Lambda:**  
  Due Lambda Python (`lambda_function.py`, `queue_processor.py`): gestiscono richieste (API Gateway) sia sincrone sia asincrone via SQS. Tutte le analytics delle raccomandazioni sono registrate su DynamoDB.

- **Pipeline CI/CD & Deploy:**  
  Automatizzazione deploy tramite `pipeline-final.yaml` (CodePipeline/CodeBuild) e `deploy.sh`. Il deploy crea ruoli IAM, repository Docker ECR, Elastic Beanstalk e Lambda.

---

## Tecnologie Utilizzate

- AWS Lambda (Python)
- API Gateway
- Amazon SQS (asincrono)
- DynamoDB
- Elastic Beanstalk (Flask Docker)
- AWS ECR/Docker
- CodePipeline & CodeBuild (CI/CD)
- HTML, CSS, JS, Chart.js

---

## Installazione e Deploy

1. **Prerequisiti:**
   - AWS CLI configurata
   - SAM CLI installata (opzionale ma consigliata)
   - Permessi AWS admin
   - Docker
