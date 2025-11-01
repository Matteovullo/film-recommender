let charts = {}; // Contenitore per le istanze di Chart.js

// Risoluzione CONFLITTO - LASCIARE UNA SOLA RIGA PULITA
let API_BASE_URL = 'https://mk9humh7rf.execute-api.eu-west-1.amazonaws.com/Prod';

async function loadAnalytics() {
    showLoading();
    
    try {
        console.log('📊 Caricamento analytics...');
        
        // Chiama l'endpoint proxy di Flask /api/analytics
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
            // Usa displayError se la risposta è success: false
            displayError('Nessun dato analytics disponibile: ' + (data.error || 'Server error'));
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
    // CHIAMATA FONDAMENTALE: Disegna i grafici con i dati reali
    drawCharts(data.metrics); 
}

// ===================================================
// FUNZIONE PER DISEGNARE I GRAFICI (Chart.js)
// ===================================================
function drawCharts(metrics) {
    const chartsContainer = document.getElementById('chartsContainer');
    if (!chartsContainer) return;
    
    chartsContainer.style.display = 'grid';

    // 1. GRAFICO DISTRIBUZIONE GENERI (Barre)
    const genres = metrics.genre_distribution || {};
    // Filtra 'unknown' o 'Error' dai generi visualizzati
    const genreLabels = Object.keys(genres).filter(g => g !== 'unknown' && g !== 'Error');
    const genreData = genreLabels.map(g => genres[g]);

    const genreCtx = document.getElementById('genreChart');
    // Distrugge l'istanza precedente per evitare sovrapposizioni
    if (charts.genreChart) charts.genreChart.destroy(); 

    charts.genreChart = new Chart(genreCtx, {
        type: 'bar',
        data: {
            labels: genreLabels,
            datasets: [{
                label: 'Raccomandazioni per Genere',
                data: genreData,
                backgroundColor: ['#3498db', '#2ecc71', '#f1c40f', '#e74c3c', '#9b59b6', '#34495e'],
                borderColor: ['#2980b9', '#27ae60', '#f39c12', '#c0392b', '#8e44ad', '#2c3e50'],
                borderWidth: 1
            }]
        },
        options: {
            responsive: true,
            scales: {
                y: { beginAtZero: true }
            }
        }
    });

    // 2. GRAFICO TASSO DI SUCCESSO (Ciambella)
    const successRate = metrics.success_rate || 0;
    const rateCtx = document.getElementById('rateChart');
    if (charts.rateChart) charts.rateChart.destroy(); 

    charts.rateChart = new Chart(rateCtx, {
        type: 'doughnut',
        data: {
            labels: ['Successo', 'Fallimento'],
            datasets: [{
                data: [successRate, 100 - successRate],
                backgroundColor: ['#2ecc71', '#e74c3c'],
                hoverOffset: 4
            }]
        },
        options: {
            responsive: true,
            plugins: {
                legend: { position: 'top' },
                title: { display: false }
            }
        }
    });
}
// ===================================================

function displayStats(metrics) {
    const statsGrid = document.getElementById('statsGrid');
    
    statsGrid.innerHTML = `
        <div class="stat-card">
            <div class="stat-number">${metrics.total_recommendations || 0}</div>
            <div class="stat-label">Raccomandazioni Totali</div>
        </div>
        <div class="stat-card">
            <div class="stat-number">${metrics.unique_users || 0}</div>
            <div class="stat-label">Utenti Unici</div>
        </div>
        <div class="stat-card">
            <div class="stat-number">${metrics.success_rate || 0}%</div>
            <div class="stat-label">Tasso di Successo</div>
        </div>
        <div class="stat-card">
            <div class="stat-number">${(metrics.genre_distribution && Object.keys(metrics.genre_distribution).length > 0) ? Object.keys(metrics.genre_distribution).filter(g => g !== 'unknown' && g !== 'Error').length : 0}</div>
            <div class="stat-label">Generi Monitorati</div>
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
    const chartsContainer = document.getElementById('chartsContainer');
    if (chartsContainer) chartsContainer.style.display = 'none';
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
    const chartsContainer = document.getElementById('chartsContainer');
    if (chartsContainer) chartsContainer.style.display = 'none';
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