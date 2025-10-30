let charts = {};

// IMPORTANTE: Usa endpoint FLASK locali
<<<<<<< HEAD
let API_BASE_URL = 'https://mk9humh7rf.execute-api.eu-west-1.amazonaws.com/Prod';
=======
let API_BASE_URL = ''; // Vuoto = stesso dominio
>>>>>>> origin/main

async function loadAnalytics() {
    showLoading();
    
    try {
        console.log('📊 Caricamento analytics...');
        
        const response = await fetch('/api/analytics', {
            headers: {
                'Accept': 'application/json'
            }
        });
        
        if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
        
        const data = await response.json();
        console.log('📈 Dati analytics:', data);
        
        if (data.status === 'success') {
            displayRealData(data);
        } else {
            displayNoData('Nessun dato analytics disponibile');
        }
        
        updateLastUpdated();
        
    } catch (error) {
        console.error('❌ Errore caricamento analytics:', error);
        displayError('Errore di connessione: ' + error.message);
    }
}

function displayRealData(data) {
    updateDataStatus('Dati in tempo reale', 'status-real');
    displayStats(data.metrics);
    displayInsights(data.insights || []);
}

function displayStats(metrics) {
    const statsGrid = document.getElementById('statsGrid');
    
    statsGrid.innerHTML = `
        <div class="stat-card">
            <div class="stat-number">${metrics.total_recommendations || 0}</div>
            <div class="stat-label">Raccomandazioni Totali</div>
            <div class="stat-subtitle">⚡ ${metrics.architecture || 'Lambda'}</div>
        </div>
        <div class="stat-card">
            <div class="stat-number">${metrics.unique_users || 1}</div>
            <div class="stat-label">Utenti Unici</div>
            <div class="stat-subtitle">🔐 Cognito</div>
        </div>
        <div class="stat-card">
            <div class="stat-number">${metrics.success_rate || 95}%</div>
            <div class="stat-label">Tasso di Successo</div>
            <div class="stat-subtitle">🚀 API Gateway</div>
        </div>
        <div class="stat-card">
            <div class="stat-number">${metrics.avg_response_time || 0.8}s</div>
            <div class="stat-label">Tempo Risposta</div>
            <div class="stat-subtitle">💨 Performant</div>
        </div>
    `;
}

function displayInsights(insights) {
    const insightsGrid = document.getElementById('insightsGrid');
    
    if (insights && insights.length > 0) {
        insightsGrid.innerHTML = insights.map(insight => `
            <div class="insight-card">
                <div>💡 ${insight}</div>
            </div>
        `).join('');
    } else {
        insightsGrid.innerHTML = `
            <div class="insight-card">
                <div>🚀 Architettura Serverless Attiva</div>
            </div>
            <div class="insight-card">
                <div>⚡ Elastic Beanstalk + Lambda</div>
            </div>
            <div class="insight-card">
                <div>💰 Costo ottimizzato</div>
            </div>
        `;
    }
}

function showLoading() {
    document.getElementById('statsGrid').innerHTML = '<div class="loading">Caricamento dati in corso...</div>';
    updateDataStatus('Caricamento...', 'status-loading');
}

function updateDataStatus(text, className) {
    const statusEl = document.getElementById('dataStatus');
    if (statusEl) {
        statusEl.textContent = text;
        statusEl.className = 'data-status ' + className;
    }
}

function updateLastUpdated() {
    const now = new Date();
    const lastUpdatedEl = document.getElementById('lastUpdated');
    if (lastUpdatedEl) {
        lastUpdatedEl.textContent = `Ultimo aggiornamento: ${now.toLocaleString('it-IT')}`;
    }
}

function displayError(message) {
    const statsGrid = document.getElementById('statsGrid');
    statsGrid.innerHTML = `
        <div class="error-card">
            <h4>❌ Errore</h4>
            <p>${message}</p>
            <button onclick="loadAnalytics()" class="btn-retry">Riprova</button>
        </div>
    `;
    updateDataStatus('Errore di caricamento', 'status-error');
}

// Inizializzazione
document.addEventListener('DOMContentLoaded', function() {
    console.log('📊 Dashboard inizializzata');
    
    const savedUser = localStorage.getItem('cognitoUser');
    if (savedUser) {
        document.getElementById('currentUser').textContent = savedUser;
    }
    
    loadAnalytics();
    
    // Aggiorna ogni 30 secondi
    setInterval(loadAnalytics, 30000);
});
