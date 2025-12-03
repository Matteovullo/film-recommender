let currentToken = localStorage.getItem('cognitoToken');
let currentUser = localStorage.getItem('cognitoUser');

let API_BASE_URL = 'https://s55sbmcqjd.execute-api.eu-west-1.amazonaws.com/Prod';

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

const POLLING_INTERVAL = 3000; 

async function startPolling(requestId, genre, recommendBtn, originalText) {
    const listDiv = document.getElementById('recommendationsList');
    
    listDiv.innerHTML = `
        <div class="info-message">
            <h4>Elaborazione in Corso...</h4>
            <p>La tua richiesta per **${genre}** è in coda SQS.</p>
            <p>Attendere il completamento del calcolo (ID: ${requestId}).</p>
            <small>Verifica stato ogni ${POLLING_INTERVAL / 1000} secondi.</small>
        </div>`;
    document.getElementById('results').style.display = 'block';

    const poll = setInterval(async () => {
        try {
            console.log(`⏱️ Polling stato per ID: ${requestId}`);
            
            const statusResponse = await fetch(`/api/recommend/status/${requestId}`, {
                method: 'GET',
                headers: {
                    'Authorization': `Bearer ${currentToken}` 
                }
            });
            const statusData = await statusResponse.json();

            if (statusResponse.status === 200 && statusData.status === 'complete') {
                
                clearInterval(poll);
                recommendBtn.innerHTML = originalText;
                recommendBtn.disabled = false;
                showMessage(`✅ Risultati per ${statusData.genre || genre} ricevuti!`, 'success');
                
                const htmlList = statusData.recommendations.map(movie => `
                    <div class="recommendation-item">
                        <h4>🎭 ${movie}</h4>
                        <p>Genere: ${statusData.genre || genre}</p>
                    </div>
                `).join('');
                listDiv.innerHTML = htmlList;

            } else if (statusResponse.status !== 202) {
                clearInterval(poll);
                recommendBtn.innerHTML = originalText;
                recommendBtn.disabled = false;
                throw new Error(statusData.error || statusData.message || 'Errore di polling inatteso.');
            }

        } catch (err) {
            clearInterval(poll);
            recommendBtn.innerHTML = originalText;
            recommendBtn.disabled = false;
            console.error('❌ Errore Polling:', err);
            showMessage('❌ Polling fallito: ' + err.message, 'error');
            listDiv.innerHTML = `<div class="error-message">Errore Polling: ${err.message}</div>`;
        }
    }, POLLING_INTERVAL);
}

window.getRecommendations = async () => {
    const genre = document.getElementById('genre').value;
    if (!genre) {
        showMessage('Seleziona un genere', 'error');
        return;
    }

    const recommendBtn = document.getElementById('recommendBtn');
    const originalText = recommendBtn.innerHTML;
    recommendBtn.innerHTML = '<span class="loading"></span> Accodamento e Avvio Polling...';
    recommendBtn.disabled = true;

    try {
        console.log('📡 Invio richiesta ASINCRONA a /api/recommend/async...');
        
        const response = await fetch('/api/recommend/async', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${currentToken}` 
            },
            body: JSON.stringify({ 
                preferences: { 
                    genre: genre,
                    userId: currentUser 
                } 
            })
        });

        const data = await response.json();

        if (response.status === 202) {
            showMessage(`🚀 Richiesta per ${genre} accodata! Avvio monitoraggio...`, 'info');
            const requestId = data.requestId;
            
            startPolling(requestId, genre, recommendBtn, originalText);
            
        } else if (!response.ok) {
            throw new Error(data.error || `Errore HTTP ${response.status}`);
        }

    } catch (err) {
        console.error('❌ Errore in getRecommendations:', err);
        showMessage('❌ Errore: ' + err.message, 'error');
        recommendBtn.innerHTML = originalText;
        recommendBtn.disabled = false;
    }
};

window.signOut = function() {
    localStorage.removeItem('cognitoToken');
    localStorage.removeItem('cognitoUser');
    window.location.href = '/?logout=true';
};

document.addEventListener('DOMContentLoaded', function() {
    console.log('🔍 Controllo autenticazione...');
    
    const savedToken = localStorage.getItem('cognitoToken');
    const savedUser = localStorage.getItem('cognitoUser');
    
    if (!savedToken || !savedUser) {
        console.log('❌ Utente non autenticato, redirect a login');
        window.location.href = '/';
    } else {
        console.log('✅ Utente autenticato:', savedUser);
        console.log('🌐 Ambiente pronto');
        
        const userNameDisplay = document.getElementById('userNameDisplay');
        if (userNameDisplay) {
             userNameDisplay.textContent = `Benvenuto, ${savedUser}!`;
        }
    }
});

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