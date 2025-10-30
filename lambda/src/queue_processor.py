import json
import boto3
import logging
import uuid
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """
    Processa i messaggi dalla coda SQS per raccomandazioni
    """
    logger.info(f"�� Processing {len(event['Records'])} recommendation requests")
    
    successful_messages = 0
    failed_messages = 0
    
    for record in event['Records']:
        try:
            message_body = json.loads(record['body'])
            logger.info(f"Processing recommendation for: {message_body}")
            
            # Elabora la raccomandazione
            result = process_recommendation(message_body)
            
            # Salva nei log/analytics
            save_recommendation_analytics(message_body, result)
            
            successful_messages += 1
            logger.info(f"✅ Successfully processed: {message_body.get('requestId', 'unknown')}")
            
        except Exception as e:
            failed_messages += 1
            logger.error(f"❌ Failed to process message: {e}")
            logger.error(f"Failed message body: {record.get('body', 'unknown')}")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'processed': successful_messages,
            'failed': failed_messages,
            'message': f'Processed {successful_messages} recommendations'
        })
    }

def process_recommendation(message_data):
    """
    Elabora una richiesta di raccomandazione
    """
    preferences = message_data.get('preferences', {})
    genre = preferences.get('genre', '').lower()
    
    # Database film per raccomandazioni
    movies_database = {
        "sci-fi": [
            "Blade Runner 2049 (SQS Processed)",
            "The Matrix (SQS Processed)", 
            "Dune (SQS Processed)"
        ],
        "fantasy": [
            "Lord of the Rings (SQS Processed)",
            "Harry Potter (SQS Processed)",
            "Pan's Labyrinth (SQS Processed)"
        ],
        "dystopian": [
            "Children of Men (SQS Processed)",
            "Snowpiercer (SQS Processed)", 
            "Mad Max (SQS Processed)"
        ],
        "thriller": [
            "Parasite (SQS Processed)",
            "Inception (SQS Processed)",
            "The Dark Knight (SQS Processed)"
        ],
        "action": [
            "John Wick (SQS Processed)",
            "Mad Max: Fury Road (SQS Processed)"
        ]
    }
    
    # Seleziona film in base al genere
    if genre in movies_database:
        recommendations = movies_database[genre]
    else:
        recommendations = ["Film consigliato 1 (SQS)", "Film consigliato 2 (SQS)"]
    
    return {
        'recommendations': recommendations[:3],  # Massimo 3 film
        'genre': genre,
        'processedAt': datetime.now().isoformat(),
        'architecture': 'SQS + Lambda Async'
    }

def save_recommendation_analytics(message_data, result):
    """
    Salva i dati delle raccomandazioni per analytics
    """
    try:
        table = dynamodb.Table('FilmRecommender-Analytics')
        
        analytics_record = {
            'eventId': str(uuid.uuid4()),
            'eventType': 'SQS_RECOMMENDATION_PROCESSED',
            'userId': message_data.get('userId', 'anonymous'),
            'genre': result.get('genre', 'unknown'),
            'recommendationsCount': len(result.get('recommendations', [])),
            'timestamp': datetime.now().isoformat(),
            'ttl': int(datetime.now().timestamp()) + 2592000  # 30 giorni
        }
        
        table.put_item(Item=analytics_record)
        logger.info(f"📊 Analytics saved: {analytics_record['eventId']}")
        
    except Exception as e:
        logger.warning(f"⚠️ Could not save analytics: {e}")
