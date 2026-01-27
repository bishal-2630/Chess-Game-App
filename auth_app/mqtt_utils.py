import json
import paho.mqtt.client as mqtt
from django.conf import settings
import logging

logger = logging.getLogger(__name__)

# MQTT Broker Settings
MQTT_BROKER = "broker.emqx.io"
MQTT_PORT = 1883
MQTT_KEEPALIVE = 60
MQTT_TOPIC_PREFIX = "chess/user/"

def publish_mqtt_notification(username, notification_type, payload):
    """
    Publishes a notification message to the user's specific MQTT topic.
    Topic format: chess/user/{username}/notifications
    """
    client = mqtt.Client()
    try:
        client.connect(MQTT_BROKER, MQTT_PORT, MQTT_KEEPALIVE)
        
        topic = f"{MQTT_TOPIC_PREFIX}{username}/notifications"
        message = {
            'type': notification_type,
            'payload': payload
        }
        
        result = client.publish(topic, json.dumps(message))
        
        # Wait for publish to complete (optional for small messages, but safer)
        result.wait_for_publish()
        
        if result.rc == mqtt.MQTT_ERR_SUCCESS:
            logger.info(f"✅ MQTT notification sent to {username} on {topic}")
            return True
        else:
            logger.error(f"❌ Failed to publish MQTT message to {username}: {result.rc}")
            return False
            
    except Exception as e:
        logger.error(f"❌ MQTT Publish Error: {str(e)}")
        return False
    finally:
        client.disconnect()
