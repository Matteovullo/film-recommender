import json
import boto3
import os
import uuid
from datetime import datetime, timedelta

dynamodb = boto3.resource('dynamodb')
sqs = boto3.client('sqs')

USER_TABLE = 'FilmRecommender-Users'
ANALYTICS_TABLE = 'FilmRecommender-Analytics'
SQS_QUEUE = 'film-recommender-analytics'

MOVIES = [
    {"title": "Blade Runner", "genre": "sci-fi"},
    {"title": "The Matrix", "genre": "sci-fi"},
    {"title": "Dune (2021)", "genre": "sci-fi"},
    {"title": "Interstellar", "genre": "sci-fi"},
    {"title": "Lord of the Rings", "genre": "fantasy"},
    {"title": "Pan's Labyrinth", "genre": "fantasy"},
    {"title": "Children of Men", "genre": "dystopian"},
    {"title": "Snowpiercer", "genre": "dystopian"},
    {"title": "Parasite", "genre": "thriller"},
    {"title": "Inception", "genre": "thriller"},
    {"title": "The Dark Knight", "genre": "thriller"},
    {"title": "Mad Max: Fury Road", "genre": "action"},
    {"title": "John Wick", "genre": "action"},
]

def lambda_handler(event, context):
    print("Event:", json.dumps(event))
    
    try:
        path = event.get('requestContext', {}).get('http', {}).get('path')
        method = event.get('requestContext', {}).get('http', {}).get('method')
        
        if path == '/api/recommend' and method == 'POST':
            return handle_recommendations(event)
        elif path == '/api/analytics' and method == 'GET':
            return handle_analytics(event)
        elif path == '/api/health' and method == 'GET':
            return handle_health()
        else:
            return {
                'statusCode': 404,
                'headers': {'Access-Control-Allow-Origin': '*'},
                'body': json.dumps({'error': 'Endpoint non trovato'})
            }
            
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'error': str(e)})
        }

def handle_recommendations(event):
    auth_header = event.get('headers', {}).get('Authorization', '')
    user_id = extract_user_id(auth_header)
    
    body = json.loads(event.get('body', '{}'))
    preferences = body.get('preferences', {})
    
    genre = preferences.get('genre', '').lower()
    filtered_movies = [movie for movie in MOVIES if movie['genre'] == genre]
    
    if not filtered_movies:
        filtered_movies = MOVIES[:3]
    else:
        filtered_movies = filtered_movies[:3]
    
    recommendations = [movie['title'] for movie in filtered_movies]
    
    save_user_data(user_id, preferences, recommendations)
    send_analytics_event(user_id, 'recommendation_request', {
        'genre': genre,
        'recommendations_count': len(recommendations)
    })
    
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json','Access-Control-Allow-Origin': '*'},
        'body': json.dumps({
            'message': 'Raccomandazioni generate!',
            'userId': user_id,
            'recommendations': recommendations,
            'architecture': 'API Gateway + Lambda'
        })
    }

def handle_analytics(event):
    auth_header = event.get('headers', {}).get('Authorization', '')
    user_id = extract_user_id(auth_header)
    
    stats = get_user_stats(user_id)
    
    return {
        'statusCode': 200,
        'headers': {'Access-Control-Allow-Origin': '*'},
        'body': json.dumps({
            'status': 'success',
            'userId': user_id,
            'metrics': {'total_recommendations': stats['eventCount'], 'unique_users': 1}
        })
    }

def handle_health():
    return {
        'statusCode': 200,
        'headers': {'Access-Control-Allow-Origin': '*'},
        'body': json.dumps({
            'status': 'healthy',
            'service': 'Film Recommender Lambda',
            'architecture': 'API Gateway + Lambda + DynamoDB + SQS'
        })
    }

def extract_user_id(auth_header):
    try:
        if auth_header.startswith('Bearer '):
            token = auth_header.split(' ', 1)[1]
            payload = token.split('.')[1]
            payload += '=' * (4 - len(payload) % 4)
            decoded = json.loads(__import__('base64').urlsafe_b64decode(payload).decode('utf-8'))
            return decoded.get('sub', 'anonymous')
    except Exception:
        pass
    return "anonymous"

def save_user_data(user_id, preferences, recommendations):
    table = dynamodb.Table(USER_TABLE)
    item = {
        'userId': user_id,
        'preferences': preferences,
        'recommendations': recommendations,
        'lastActivity': datetime.now().isoformat(),
        'ttl': int((datetime.now() + timedelta(days=90)).timestamp())
    }
    table.put_item(Item=item)

def send_analytics_event(user_id, event_type, data):
    queue_url = sqs.get_queue_url(QueueName=SQS_QUEUE)['QueueUrl']
    message = {
        'eventId': str(uuid.uuid4()),
        'userId': user_id,
        'eventType': event_type,
        'data': data,
        'timestamp': datetime.now().isoformat()
    }
    sqs.send_message(QueueUrl=queue_url, MessageBody=json.dumps(message))

def get_user_stats(user_id):
    try:
        table = dynamodb.Table(ANALYTICS_TABLE)
        response = table.scan(FilterExpression='userId = :user_id', ExpressionAttributeValues={':user_id': user_id})
        return {'eventCount': response.get('Count', 0)}
    except Exception:
        return {'eventCount': 0}
