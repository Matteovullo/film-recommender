echo " SETUP GITHUB TOKEN PER AWS CODEPIPELINE"

read -sp "Incolla il tuo GitHub Token: " GITHUB_TOKEN
echo

read -p "Inserisci il tuo GitHub Username: " GITHUB_USERNAME

echo " Verifico il token..."
curl -s -H "Authorization: token $GITHUB_TOKEN" \
     https://api.github.com/user | grep '"login":'

if [ $? -eq 0 ]; then
    echo " Token valido!"

    export GITHUB_TOKEN="$GITHUB_TOKEN"
    export GITHUB_USERNAME="$GITHUB_USERNAME"
    
    echo " Configurazione:"
    echo "   Username: $GITHUB_USERNAME"
    echo "   Token: ${GITHUB_TOKEN:0:8}... (primi 8 caratteri)"
    
    read -p "Vuoi creare un file di configurazione? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cat > github-config.env << CONFIG
export GITHUB_USERNAME="$GITHUB_USERNAME"
export GITHUB_TOKEN="$GITHUB_TOKEN"
CONFIG
        echo " File github-config.env creato"
        echo "  ATTENZIONE: Questo file contiene il token in chiaro!"
        echo "   Eliminalo dopo l'uso: rm github-config.env"
    fi
    
else
    echo "   Token non valido!"
    echo "   Controlla di aver copiato tutto correttamente"
fi
