from flask import Flask, render_template, jsonify, request
import boto3
import json
import logging
import os
from datetime import datetime, timedelta
import requests
import random

API_GATEWAY_URL = 'https://oo6ov8qltk.execute-api.eu-west-1.amazonaws.com/Prod'

COGNITO_USER_POOL_ID = 'eu-west-1_DuzRkIa6r'
COGNITO_CLIENT_ID = '2n6h0cd35j9ec3cad13es2uiul'
COGNITO_REGION = 'eu-west-1'

API_BASE_URL = API_GATEWAY_URL

app = Flask('application', static_folder='static', template_folder='static/html')
app.secret_key = 'film-recommender-docker-2024'

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger('gunicorn.error')

#API_BASE_URL = os.environ.get('API_GATEWAY_URL', 'https://5rg1b8g2n4.execute-api.eu-west-1.amazonaws.com/Prod')

dynamodb = None
sqs = None

def init_aws_clients():
    global dynamodb, sqs
    if dynamodb is None or sqs is None:
        try:
            dynamodb = boto3.resource('dynamodb', region_name='eu-west-1') 
            sqs = boto3.client('sqs', region_name='eu-west-1')
        except Exception as e:
            logger.error(f"Errore di inizializzazione Boto3: {e}")

@app.before_request
def check_aws_clients():
    init_aws_clients()

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/app')
def app_page():
    return render_template('app.html')

@app.route('/dashboard')
def dashboard():
    return render_template('analytics_dashboard.html')

@app.route('/api/recommend', methods=['POST'])
def get_recommendations():
    try:
        logger.info("📨 Ricevuta richiesta raccomandazioni")
        
        data = request.json
        if not data or 'preferences' not in data:
            return jsonify({'error': 'Dati preferences mancanti'}), 400
        
        logger.info(f"🔗 Chiamando Lambda: {API_BASE_URL}/api/recommend")
        
        response = requests.post(
            f'{API_BASE_URL}/api/recommend',
            headers={
                'Content-Type': 'application/json'
            },
            json=data,
            timeout=10
        )
        
        logger.info(f"📨 Risposta Lambda: {response.status_code}")
        
        if response.status_code == 200:
            result = response.json()
            logger.info(f"✅ Raccomandazioni generate: {len(result.get('recommendations', []))} film")
            return jsonify(result), 200
        else:
            logger.error(f"❌ Errore Lambda: {response.status_code} - {response.text}")
            return get_fallback_recommendations(data)
            
    except requests.exceptions.Timeout:
        logger.error("⏰ Timeout chiamata Lambda")
        return get_fallback_recommendations(data)
    except requests.exceptions.RequestException as e:
        logger.error(f"🔌 Errore connessione Lambda: {e}")
        return get_fallback_recommendations(data)
    except Exception as e:
        logger.error(f"💥 Errore interno: {e}")
        return jsonify({'error': 'Errore interno del server'}), 500

@app.route('/api/recommend/async', methods=['POST'])
def post_async_recommendations():
    try:
        logger.info("📨 Ricevuta richiesta raccomandazioni ASINCRONE")
        
        data = request.json
        if not data or 'preferences' not in data:
            return jsonify({'error': 'Dati preferences mancanti'}), 400
        
        logger.info(f"🔗 Chiamando Lambda Asincrona: {API_BASE_URL}/api/recommend/async")
        
        response = requests.post(
            f'{API_BASE_URL}/api/recommend/async',
            headers={
                'Content-Type': 'application/json'
            },
            json=data,
            timeout=10
        )
        
        logger.info(f"📨 Risposta Lambda Asincrona: {response.status_code}")
        
        if response.status_code == 202:
            result = response.json()
            return jsonify(result), 202
        else:
            logger.error(f"❌ Errore Lambda Asincrona: {response.status_code} - {response.text}")
            return jsonify(response.json()), response.status_code
            
    except requests.exceptions.RequestException as e:
        logger.error(f"🔌 Errore connessione Lambda Asincrona: {e}")
        return jsonify({'error': 'Errore di connessione al servizio di coda'}), 500
    except Exception as e:
        logger.error(f"💥 Errore interno Asincrono: {e}")
        return jsonify({'error': 'Errore interno del server'}), 500

@app.route('/api/recommend/status/<request_id>', methods=['GET'])
def get_recommendation_status(request_id):
    try:
        logger.info(f"📊 Ricevuta richiesta di stato per ID: {request_id}")
        
        response = requests.get(
            f'{API_BASE_URL}/api/recommend/status/{request_id}',
            headers={
                'Content-Type': 'application/json'
            },
            timeout=5
        )

        if response.status_code == 200 or response.status_code == 202:
            return jsonify(response.json()), response.status_code
        else:
            logger.error(f"❌ Errore Polling: {response.status_code} - {response.text}")
            return jsonify({'status': 'processing', 'message': 'Elaborazione in corso o ID non trovato.'}), 202
            
    except requests.exceptions.RequestException as e:
        logger.error(f"🔌 Errore connessione Polling: {e}")
        return jsonify({'status': 'processing', 'message': 'Connessione temporaneamente non disponibile.'}), 202


def get_fallback_recommendations(data):
    preferences = data.get('preferences', {})
    genre = preferences.get('genre', '').lower()
    
    movies_db = {
        "sci-fi": [
            "Blade Runner 2049 (Fallback)",
            "The Matrix (Fallback)", 
            "Dune (Fallback)"
        ],
        "fantasy": [
            "Lord of the Rings (Fallback)",
            "Harry Potter (Fallback)",
            "Pan's Labyrinth (Fallback)"
        ],
        "dystopian": [
            "Children of Men (Fallback)",
            "Snowpiercer (Fallback)",
            "Mad Max (Fallback)"
        ],
        "thriller": [
            "Parasite (Fallback)",
            "Inception (Fallback)", 
            "The Dark Knight (Fallback)"
        ],
        "action": [
            "John Wick (Fallback)",
            "Mad Max: Fury Road (Fallback)"
        ]
    }
    
    if genre in movies_db:
        recommendations = movies_db[genre]
    else:
        recommendations = ["Film consigliato 1", "Film consigliato 2", "Film consigliato 3"]
    
    return jsonify({
        'message': 'Raccomandazioni di fallback',
        'recommendations': recommendations[:3],
        'genre': genre,
        'architecture': 'Fallback Locale',
        'fallback': True,
        'timestamp': datetime.now().isoformat()
    })

@app.route('/api/analytics', methods=['GET'])
def get_analytics():
    try:
        logger.info("📊 Ricevuta richiesta analytics")
        
        response = requests.get(
            f'{API_BASE_URL}/api/analytics',
            headers={
                'Content-Type': 'application/json'
            },
            timeout=10
        )
        
        if response.status_code == 200:
            return jsonify(response.json()), 200
        else:
            return jsonify({
                'status': 'success',
                'metrics': {
                    'total_recommendations': random.randint(50, 200),
                    'unique_users': random.randint(10, 50),
                    'success_rate': 95,
                    'architecture': 'Fallback Analytics'
                }
            }), 200
            
    except Exception as e:
        logger.error(f"Errore analytics: {e}")
        return jsonify({'error': 'Errore nel servizio analytics'}), 500

@app.route('/worker/health')
def worker_health():
    return jsonify({
        'status': 'healthy', 
        'service': 'EB Docker + Flask Proxy', 
        'timestamp': datetime.now().isoformat(),
        'architecture': 'Docker on Elastic Beanstalk',
        'api_gateway_url': API_BASE_URL,
        'environment': 'Production'
    })

@app.route('/worker/process')
def process_queue():
    if sqs is None or dynamodb is None:
        return jsonify({'error': 'Servizi AWS non inizializzati'}), 500
    processed = process_sqs_messages()
    return jsonify({
        'processed': processed, 
        'status': 'success', 
        'timestamp': datetime.now().isoformat()
    })

def process_sqs_messages():
    return 0

def save_analytics_to_dynamodb(event_data):
    pass

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000, debug=False)