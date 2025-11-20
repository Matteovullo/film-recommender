import json
import boto3
import logging
import uuid
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    logger.info(f" Processing {len(event['Records'])} recommendation requests")
    
    successful_messages = 0
    failed_messages = 0
    
    for record in event['Records']:
        try:
            message_body = json.loads(record['body'])
            logger.info(f"Processing recommendation for: {message_body}")
            
            result = process_recommendation(message_body)
            
            save_recommendation_analytics(message_body, result)
            
            successful_messages += 1
            logger.info(f"Successfully processed: {message_body.get('requestId', 'unknown')}")
            
        except Exception as e:
            failed_messages += 1
            logger.error(f"Failed to process message: {e}")
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
    preferences = message_data.get('preferences', {})
    genre = preferences.get('genre', '').lower()
    
    movies_database = {
        "sci-fi": [
            "Blade Runner 2049",
            "The Matrix", 
            "Dune"
        ],
        "fantasy": [
            "Lord of the Rings",
            "Harry Potter",
            "Pan's Labyrinth"
        ],
        "dystopian": [
            "Children of Men",
            "Snowpiercer", 
            "Mad Max"
        ],
        "thriller": [
            "Parasite",
            "Inception",
            "The Dark Knight"
        ],
        "action": [
            "John Wick",
            "Mad Max: Fury Road"
        ]
    }
    
    if genre in movies_database:
        recommendations = movies_database[genre]
    else:
        recommendations = ["Film consigliato 1", "Film consigliato 2"]
    
    return {
        'recommendations': recommendations[:3], 
        'genre': genre,
        'processedAt': datetime.now().isoformat(),
        'architecture': 'SQS + Lambda Async'
    }

def save_recommendation_analytics(message_data, result):
    try:
        table = dynamodb.Table('FilmRecommender-Analytics-v2') 
        
        analytics_record = {
            'eventId': str(uuid.uuid4()),
            'eventType': 'SQS_RECOMMENDATION_PROCESSED',
            'userId': message_data.get('userId', 'anonymous'),
            'genre': result.get('genre', 'unknown'),
            'recommendationsCount': len(result.get('recommendations', [])),
            'timestamp': datetime.now().isoformat(),
            'ttl': int(datetime.now().timestamp()) + 2592000 
        }
        
        analytics_record['requestId'] = message_data.get('requestId', 'unknown') 

        table.put_item(Item=analytics_record)
        logger.info(f"📊 Analytics saved: {analytics_record['eventId']}")
        
    except Exception as e:
        logger.warning(f"Could not save analytics: {e}")