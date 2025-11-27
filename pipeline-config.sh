#!/bin/bash
# CONFIGURAZIONE PIPELINE

REGION="eu-west-1"
APP_NAME="film-recommender-final"
LAMBDA_STACK="$APP_NAME-lambda"
ENV_NAME="$APP_NAME-env"
PIPELINE_BASE_NAME="film-pipe"  # NOME MOLTO CORTO

# Configurazione GitHub
GITHUB_OWNER="Matteovullo"
GITHUB_REPO="film-recommender"
GITHUB_BRANCH="main"

# Verifica token GitHub
if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ ERRORE: GITHUB_TOKEN non impostato"
    echo "Esporta il token con: export GITHUB_TOKEN='tuo-token-github'"
    exit 1
fi

export REGION APP_NAME LAMBDA_STACK ENV_NAME PIPELINE_BASE_NAME
export GITHUB_OWNER GITHUB_REPO GITHUB_BRANCH GITHUB_TOKEN