from flask import Flask, render_template, jsonify, request
import boto3
import json
import logging
import os
from datetime import datetime, timedelta
import requests
import random

# Inizializza Flask
app = Flask('application', static_folder='static', template_folder='static/html')
app.secret_key = 'film-recommender-docker-2024'

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger('gunicorn.error')

# URL API Gateway - per chiamate dirette
API_BASE_URL = os.environ.get('API_GATEWAY_URL', 'https://mk9humh7rf.execute-api.eu-west-1.amazonaws.com/Prod')

# Inizializzazione Boto3
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

# Endpoint per ottenere raccomandazioni - CHIAMATA DIRETTA A LAMBDA
@app.route('/api/recommend', methods=['POST'])
def get_recommendations():
    try:
        logger.info("📨 Ricevuta richiesta raccomandazioni")
        
        # Prepara i dati per la Lambda
        data = request.json
        if not data or 'preferences' not in data:
            return jsonify({'error': 'Dati preferences mancanti'}), 400
        
        # CHIAMATA DIRETTA all'API Gateway Lambda
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
            # Fallback: raccomandazioni locali
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

# Fallback per raccomandazioni locali
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

# Endpoint per analytics - CHIAMATA DIRETTA A LAMBDA
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
            # Fallback analytics
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

# Endpoints Worker
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

@app.route('/worker/stats')
def worker_stats():
    if sqs is None:
        return jsonify({'error': 'Servizi AWS non inizializzati'}), 500
        
    try:
        queue_url = sqs.get_queue_url(QueueName='film-recommender-analytics')['QueueUrl']
        response = sqs.get_queue_attributes(
            QueueUrl=queue_url,
            AttributeNames=['ApproximateNumberOfMessages', 'ApproximateNumberOfMessagesNotVisible']
        )
        attributes = response['Attributes']
        return jsonify({
            'queue_name': 'film-recommender-analytics',
            'messages_available': int(attributes.get('ApproximateNumberOfMessages', 0)),
            'messages_in_flight': int(attributes.get('ApproximateNumberOfMessagesNotVisible', 0)),
            'region': 'eu-west-1',
            'environment': 'Docker'
        })
    except Exception as e:
        logger.error(f"Errore SQS in worker_stats: {e}")
        return jsonify({'error': str(e)}), 500

def process_sqs_messages():
    try:
        queue_url = sqs.get_queue_url(QueueName='film-recommender-analytics')['QueueUrl']
        response = sqs.receive_message(
            QueueUrl=queue_url,
            MaxNumberOfMessages=10,
            WaitTimeSeconds=5
        )
        
        messages = response.get('Messages', [])
        processed_count = 0
        
        for message in messages:
            try:
                body = json.loads(message['Body'])
                save_analytics_to_dynamodb(body)
                sqs.delete_message(QueueUrl=queue_url, ReceiptHandle=message['ReceiptHandle'])
                processed_count += 1
            except Exception as e:
                logger.error(f"Errore elaborazione messaggio: {e}")
                
        return processed_count
        
    except Exception as e:
        logger.error(f"Errore SQS in process_sqs_messages: {e}")
        return 0

def save_analytics_to_dynamodb(event_data):
    try:
        table = dynamodb.Table('FilmRecommender-Analytics')
        event = {
            'eventId': event_data.get('eventId'),
            'userId': event_data['userId'],
            'eventType': event_data['eventType'],
            'data': event_data['data'],
            'timestamp': event_data.get('timestamp', datetime.now().isoformat()),
            'ttl': int((datetime.now() + timedelta(days=30)).timestamp())
        }
        table.put_item(Item=event)
        logger.info(f"Evento salvato: {event_data['eventType']}")
    except Exception as e:
        logger.error(f"Errore salvataggio DynamoDB: {e}")

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000, debug=False)
