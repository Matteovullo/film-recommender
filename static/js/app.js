let currentToken = localStorage.getItem('cognitoToken');
let currentUser = localStorage.getItem('cognitoUser');

// Risoluzione CONFLITTO - LASCIARE UNA SOLA RIGA PULITA
let API_BASE_URL = 'https://mk9humh7rf.execute-api.eu-west-1.amazonaws.com/Prod';

function showMessage(text, type = 'info') {
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
    // ... (Logica del pulsante)
    const genre = document.getElementById('genre').value;
    if (!genre) {
        showMessage('Seleziona un genere', 'error');
        return;
    }

    const recommendBtn = document.getElementById('recommendBtn');
    const originalText = recommendBtn.innerHTML;
    recommendBtn.innerHTML = '<span class="loading"></span> Elaborazione...';
    recommendBtn.disabled = true;

    try {
        console.log('📡 Invio richiesta a /api/recommend...');
        
        // CHIAMA L'ENDPOINT FLASK LOCALE (/api/recommend)
        const response = await fetch('/api/recommend', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${currentToken}` 
            },
            body: JSON.stringify({ 
                preferences: { 
                    genre: genre 
                } 
            })
        });

        const data = await response.json();

        if (!response.ok) {
            throw new Error(data.error || `Errore HTTP ${response.status}`);
        }

        let htmlList = '';
        if (data.recommendations && data.recommendations.length > 0) {
            htmlList = data.recommendations.map(movie => `
                <div class="recommendation-item">
                    <h4>🎭 ${movie}</h4>
                    <p>Genere: ${data.genre || genre}</p>
                    <small>Architettura: ${data.architecture}</small>
                </div>
            `).join('');
            showMessage(`✅ Raccomandazioni trovate per ${data.genre || genre}!`, 'success');
        } else {
            htmlList = '<p>Nessun film trovato con le tue preferenze.</p>';
            showMessage('Nessuna raccomandazione trovata', 'info');
        }

        document.getElementById('recommendationsList').innerHTML = htmlList;
        document.getElementById('results').style.display = 'block';

    } catch (err) {
        console.error('❌ Errore in getRecommendations:', err);
        document.getElementById('recommendationsList').innerHTML = `
            <div class="error-message">
                <h4>Errore: Impossibile ottenere raccomandazioni</h4>
                <p>${err.message}</p>
                <small>Riprova più tardi</small>
            </div>`;
        document.getElementById('results').style.display = 'block';
        showMessage('❌ Errore: ' + err.message, 'error');
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
    }
});

// Stile per i messaggi
const style = document.createElement('style');
style.textContent = `
    .success-message { background: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
    .error-message { background: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
    .info-message { background: #d1ecf1; color: #0c5460; border: 1px solid #bee5eb; }
    .loading {
        display: inline-block;
        width: 1em;
        height: 1em;
        border: 2px solid #fff;
        border-radius: 50%;
        border-top-color: transparent;
        animation: spin 1s linear infinite;
        vertical-align: middle;
        margin-right: 5px;
    }
    @keyframes spin {
        to { transform: rotate(360deg); }
    }
`;
document.head.appendChild(style);