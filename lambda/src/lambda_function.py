import json
import boto3
import uuid
from datetime import datetime

def lambda_handler(event, context):
    print("Event:", json.dumps(event))
    
    headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type,Authorization,X-Amz-Date,X-Api-Key,X-Amz-Security-Token'
    }
    
    # Handle preflight
    if event.get('httpMethod') == 'OPTIONS':
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({'status': 'OK'})
        }
    
    path = event.get('path', '')
    method = event.get('httpMethod', '')
    
    if path == '/api/recommend' and method == 'POST':
        return handle_recommendations(event, headers)
    elif path == '/api/recommend/async' and method == 'POST':  # NUOVO ENDPOINT SQS
        return handle_async_recommendation(event)
    elif path == '/api/analytics' and method == 'GET':
        return handle_analytics(event, headers)
    elif path == '/api/health' and method == 'GET':
        return handle_health(headers)
    else:
        return {
            'statusCode': 404,
            'headers': headers,
            'body': json.dumps({'error': 'Endpoint non trovato: ' + path})
        }

def handle_recommendations(event, headers):
    try:
        body = json.loads(event.get('body', '{}'))
        preferences = body.get('preferences', {})
        genre = preferences.get('genre', '').lower()
        
        # Database film
        movies_db = {
            "sci-fi": [
                "Blade Runner 2049 (2017)",
                "The Matrix (1999)", 
                "Dune (2021)",
                "Interstellar (2014)",
                "Arrival (2016)"
            ],
            "fantasy": [
                "The Lord of the Rings (2001)",
                "Harry Potter (2001)",
                "Pan's Labyrinth (2006)",
                "The Princess Bride (1987)"
            ],
            "dystopian": [
                "Children of Men (2006)",
                "Snowpiercer (2013)",
                "Mad Max: Fury Road (2015)"
            ],
            "thriller": [
                "Parasite (2019)",
                "Inception (2010)",
                "The Dark Knight (2008)"
            ],
            "action": [
                "John Wick (2014)",
                "Mad Max: Fury Road (2015)"
            ]
        }
        
        # Seleziona film in base al genere
        if genre in movies_db:
            movies = movies_db[genre]
        else:
            movies = ["Blade Runner 2049 (2017)", "The Matrix (1999)", "Inception (2010)"]
        
        # Limita a 3 film
        recommendations = movies[:3]
        
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({
                'message': 'Raccomandazioni generate!',
                'recommendations': recommendations,
                'genre': genre,
                'architecture': 'API Gateway + Lambda',
                'timestamp': datetime.now().isoformat()
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 400,
            'headers': headers,
            'body': json.dumps({'error': str(e)})
        }

def handle_async_recommendation(event):
    """
    NUOVO ENDPOINT per raccomandazioni asincrone via SQS
    """
    try:
        body = json.loads(event.get('body', '{}'))
        preferences = body.get('preferences', {})
        user_id = body.get('userId', 'anonymous')
        
        # Valida input
        if not preferences.get('genre'):
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Genre is required'})
            }
        
        # Invia alla coda SQS
        sqs_result = send_to_sqs_queue(preferences, user_id)
        
        if sqs_result:
            return {
                'statusCode': 202,  # Accepted - elaborazione asincrona
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({
                    'message': 'Recommendation request queued for processing',
                    'requestId': sqs_result['requestId'],
                    'sqsMessageId': sqs_result['messageId'],
                    'status': 'processing',
                    'architecture': 'SQS + Async Lambda'
                })
            }
        else:
            return {
                'statusCode': 500,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Failed to queue request'})
            }
            
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e)})
        }

def send_to_sqs_queue(user_preferences, user_id="anonymous"):
    """
    Invia una richiesta di raccomandazione alla coda SQS
    """
    try:
        sqs_client = boto3.client('sqs')
        
        # Ottieni URL coda
        response = sqs_client.get_queue_url(QueueName='film-recommender-queue')
        queue_url = response['QueueUrl']
        
        message_body = {
            'requestId': str(uuid.uuid4()),
            'userId': user_id,
            'preferences': user_preferences,
            'timestamp': datetime.now().isoformat(),
            'source': 'API_Gateway_Async'
        }
        
        response = sqs_client.send_message(
            QueueUrl=queue_url,
            MessageBody=json.dumps(message_body),
            MessageGroupId='recommendations'
        )
        
        print(f"✅ Sent to SQS: {message_body['requestId']}")
        return {
            'messageId': response['MessageId'],
            'requestId': message_body['requestId'],
            'status': 'queued'
        }
        
    except Exception as e:
        print(f"❌ Error sending to SQS: {e}")
        return None

def handle_analytics(event, headers):
    return {
        'statusCode': 200,
        'headers': headers,
        'body': json.dumps({
            'status': 'success',
            'metrics': {
                'total_recommendations': 150,
                'unique_users': 42,
                'success_rate': 98,
                'most_popular_genre': 'sci-fi'
            },
            'architecture': 'Lambda + API Gateway'
        })
    }

def handle_health(headers):
    return {
        'statusCode': 200,
        'headers': headers,
        'body': json.dumps({
            'status': 'healthy',
            'service': 'Film Recommender Lambda',
            'timestamp': datetime.now().isoformat()
        })
    }
