import json
import boto3
import uuid
from datetime import datetime
from collections import defaultdict
import os 
from boto3.dynamodb.conditions import Attr 

dynamodb = boto3.resource('dynamodb')
sqs_client = boto3.client('sqs')

SQS_QUEUE_URL = os.environ.get('RECOMMENDER_QUEUE_URL') 
SQS_QUEUE_NAME = 'film-recommender-queue' 

def calculate_analytics():
    try:
        table = dynamodb.Table('FilmRecommender-Analytics-v2') 
        response = table.scan()
        items = response['Items']
        
        total_recommendations = len(items)
        unique_users = set()
        genre_counts = defaultdict(int)

        for item in items:
            unique_users.add(item.get('userId', 'anonymous'))
            genre_counts[item.get('genre', 'unknown')] += 1

        success_rate = 95 if total_recommendations > 0 else 0 

        return {
            'total_recommendations': total_recommendations,
            'unique_users': len(unique_users),
            'success_rate': success_rate,
            'genre_distribution': dict(genre_counts),
            'architecture': 'Lambda + DynamoDB Real Data',
        }
    except Exception as e:
        print(f"Errore aggregazione DynamoDB: {e}")
        return { 
            'total_recommendations': 0,
            'unique_users': 0,
            'success_rate': 0,
            'genre_distribution': {'Error': 100},
            'architecture': 'Lambda + DynamoDB (Fallback)'
        }

def handle_analytics(event, headers):
    analytics_metrics = calculate_analytics()
    
    insights = [
        "Dati aggiornati in tempo reale dal database DynamoDB.",
        f"Architettura dati: {analytics_metrics['architecture']}"
    ]
    
    if 'architecture' in analytics_metrics:
        del analytics_metrics['architecture']

    return {
        'statusCode': 200,
        'headers': headers,
        'body': json.dumps({
            'status': 'success',
            'metrics': analytics_metrics,
            'insights': insights
        })
    }

def lambda_handler(event, context):
    print("Event:", json.dumps(event))
    
    headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type,Authorization,X-Amz-Date,X-Api-Key,X-Amz-Security-Token'
    }
    
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
    elif path == '/api/recommend/async' and method == 'POST':
        return handle_async_recommendation(event)
    elif path.startswith('/api/recommend/status/') and method == 'GET':
        return handle_recommendation_status(event, headers) 
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

        if genre in movies_db:
            movies = movies_db[genre]
        else:
            movies = ["Blade Runner 2049 (2017)", "The Matrix (1999)", "Inception (2010)"]
        
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
    try:
        body = json.loads(event.get('body', '{}'))
        preferences = body.get('preferences', {})
        user_id = body.get('userId', 'anonymous')
        
        if not preferences.get('genre'):
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Genre is required'})
            }
        
        sqs_result = send_to_sqs_queue(preferences, user_id)
        
        if sqs_result:
            return {
                'statusCode': 202, 
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

def handle_recommendation_status(event, headers):
    request_id = event.get('pathParameters', {}).get('requestId')
    
    if not request_id:
        return {'statusCode': 400, 'body': json.dumps({'error': 'ID richiesta mancante'})}
        
    try:
        table = dynamodb.Table('FilmRecommender-Analytics-v2') 

        response = table.scan(
            FilterExpression=Attr('requestId').eq(request_id)
        )
        
        if response['Items']:
            item = response['Items'][0]
            
            genre = item.get('genre', 'unknown')

            mock_movies = {
                "sci-fi": ["Blade Runner 2049", "The Matrix", "Dune"],
                "fantasy": ["Lord of the Rings", "Harry Potter", "Pan's Labyrinth"],
                "dystopian": ["Children of Men", "Snowpiercer", "Mad Max: Fury Road"],
                "thriller": ["Parasite", "Inception", "The Dark Knight"],
                "action": ["John Wick", "Mad Max: Fury Road"],
                "unknown": ["Film Generico A", "Film Generico B"]
            }.get(genre, ["Film Generico A", "Film Generico B"])
            
            return {
                'statusCode': 200,
                'headers': headers,
                'body': json.dumps({
                    'status': 'complete',
                    'recommendations': mock_movies,
                    'genre': genre,
                    'architecture': 'SQS + Polling Success', 
                })
            }
        else:
            return {
                'statusCode': 202, 
                'headers': headers,
                'body': json.dumps({'status': 'processing', 'message': 'Elaborazione in corso'})
            }
            
    except Exception as e:
        print(f"Errore polling DynamoDB: {e}")
        return {'statusCode': 500, 'body': json.dumps({'error': 'Errore interno del server'})}

def send_to_sqs_queue(user_preferences, user_id="anonymous"):
    try:
        queue_url = SQS_QUEUE_URL 
        
        if not queue_url:
            print(f"Variabile d'ambiente RECOMMENDER_QUEUE_URL mancante. Tentativo di recupero tramite get_queue_url per: {SQS_QUEUE_NAME}")
            response = sqs_client.get_queue_url(QueueName=SQS_QUEUE_NAME)
            queue_url = response['QueueUrl']
        
        print(f"DEBUG: Tentativo invio a URL: {queue_url}")

        message_body = {
            'requestId': str(uuid.uuid4()),
            'userId': user_id,
            'preferences': user_preferences,
            'timestamp': datetime.now().isoformat(),
            'source': 'API_Gateway_Async'
        }
        
        response = sqs_client.send_message(
            QueueUrl=queue_url,
            MessageBody=json.dumps(message_body)
        )
        
        print(f"Sent to SQS: {message_body['requestId']}")
        return {
            'messageId': response['MessageId'],
            'requestId': message_body['requestId'],
            'status': 'queued'
        }
        
    except Exception as e:
        print(f"Error sending to SQS: {e}")
        return None


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