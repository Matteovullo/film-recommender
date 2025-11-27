#!/bin/bash
set -e

echo "======================================================"
echo " 🚀 DEPLOY COMPLETO AUTOMATICO"
echo "======================================================"

# Verifica GITHUB_TOKEN
if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ ERRORE: GITHUB_TOKEN non impostato"
    echo "Esporta il token: export GITHUB_TOKEN='tuo-token'"
    exit 1
fi

# FASE 1: Pulizia
echo "FASE 1: Pulizia totale..."
./1-cleanup-everything.sh

# FASE 2: Infrastruttura
echo "FASE 2: Setup infrastruttura..."
./2-setup-infrastructure.sh

# FASE 3: ECR e Docker
echo "FASE 3: Setup ECR e Docker..."
./3-deploy-ecr-and-docker.sh

# FASE 4: Pipeline
echo "FASE 4: Creazione pipeline CI/CD..."
./4-create-pipeline.sh

echo "======================================================"
echo " ✅ DEPLOY COMPLETATO CON SUCCESSO!"
echo "======================================================"
echo "Tutte le risorse sono state create correttamente"
echo "La pipeline CI/CD è attiva e sta eseguendo il deploy"
echo ""
echo "Per monitorare:"
echo "  ./pipeline-manager.sh status"
echo ""
echo "Credenziali test:"
echo "  Email: test@filmrecommender.com"
echo "  Password: Password123!"