let currentToken = localStorage.getItem('cognitoToken');
let currentUser = localStorage.getItem('cognitoUser');

// IMPORTANTE: Usa gli endpoint FLASK locali, non API Gateway diretto
<<<<<<< HEAD
let API_BASE_URL = 'https://mk9humh7rf.execute-api.eu-west-1.amazonaws.com/Prod';
=======
let API_BASE_URL = ''; // Vuoto = stesso dominio
>>>>>>> origin/main

function showMessage(text, type = 'info') {
    // Crea un messaggio visibile nell'UI
    const messageDiv = document.getElementById('message') || createMessageDiv();
    messageDiv.textContent = text;
    messageDiv.className = `message ${type}-message`;
    messageDiv.style.display = 'block';
    
    setTimeout(() => {
        messageDiv.style.display = 'none';
    }, 5000);
}

function createMessageDiv() {
    const div = document.createElement('div');
    div.id = 'message';
    div.style.cssText = 'position:fixed; top:20px; right:20px; padding:15px; border-radius:5px; z-index:1000;';
    document.body.appendChild(div);
    return div;
}

window.getRecommendations = async () => {
    const genre = document.getElementById('genre').value;
    if (!genre) {
        showMessage('Seleziona un genere', 'error');
        return;
    }

    const recommendBtn = document.getElementById('recommendBtn');
    const originalText = recommendBtn.innerHTML;
    recommendBtn.innerHTML = '🎬 Elaborazione...';
    recommendBtn.disabled = true;

    try {
        console.log('📡 Invio richiesta raccomandazioni per genere:', genre);
        
        // CHIAMA L'ENDPOINT FLASK LOCALE (/api/recommend)
        const response = await fetch('/api/recommend', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json'
            },
            body: JSON.stringify({ 
                preferences: { 
                    genre: genre 
                } 
            })
        });

        console.log('📨 Stato risposta:', response.status);

        if (!response.ok) {
            const errorText = await response.text();
            console.error('❌ Errore HTTP:', response.status, errorText);
            throw new Error(`Errore server: ${response.status}`);
        }

        const result = await response.json();
        console.log('🎯 Risultato ricevuto:', result);

        if (result.recommendations && result.recommendations.length > 0) {
            document.getElementById('recommendationsList').innerHTML = 
                result.recommendations.map(movie => `
                    <div class="recommendation-item">
                        <h4>🎭 ${movie}</h4>
                        <p>Genere: ${genre}</p>
                        <small>${result.architecture} • ${new Date().toLocaleTimeString()}</small>
                    </div>
                `).join('');
            document.getElementById('results').style.display = 'block';
            showMessage(`✅ Trovate ${result.recommendations.length} raccomandazioni!`, 'success');
        } else {
            document.getElementById('recommendationsList').innerHTML = 
                '<div class="recommendation-item">😔 Nessuna raccomandazione disponibile per questo genere</div>';
            document.getElementById('results').style.display = 'block';
            showMessage('Nessuna raccomandazione trovata', 'info');
        }

    } catch (err) {
        console.error('❌ Errore completo:', err);
        showMessage('❌ Errore: ' + err.message, 'error');
        
        // Fallback UI
        document.getElementById('recommendationsList').innerHTML = `
            <div class="recommendation-item error">
                <h4>⚠️ Errore di connessione</h4>
                <p>${err.message}</p>
                <small>Riprova più tardi</small>
            </div>`;
        document.getElementById('results').style.display = 'block';
    } finally {
        recommendBtn.innerHTML = originalText;
        recommendBtn.disabled = false;
    }
};

window.signOut = function() {
    localStorage.removeItem('cognitoToken');
    localStorage.removeItem('cognitoUser');
    window.location.href = '/?logout=true';
};

// Verifica autenticazione al caricamento
document.addEventListener('DOMContentLoaded', function() {
    console.log('🔍 Controllo autenticazione...');
    
    if (!currentToken || !currentUser) {
        console.log('❌ Utente non autenticato, redirect a login');
        window.location.href = '/';
    } else {
        console.log('✅ Utente autenticato:', currentUser);
        console.log('🌐 Ambiente pronto');
        
        // Aggiungi gestore eventi migliore al bottone
        const recommendBtn = document.getElementById('recommendBtn');
        if (recommendBtn) {
            recommendBtn.addEventListener('click', getRecommendations);
        }
    }
});

// Stile per i messaggi
const style = document.createElement('style');
style.textContent = `
    .success-message { background: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
    .error-message { background: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
    .info-message { background: #d1ecf1; color: #0c5460; border: 1px solid #bee5eb; }
`;
document.head.appendChild(style);
