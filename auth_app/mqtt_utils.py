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
    logger.info(f"🔔 MQTT PUBLISH: Starting publish for user '{username}', type '{notification_type}'")
    
    client = mqtt.Client()
    try:
        logger.info(f"🔌 MQTT: Connecting to broker {MQTT_BROKER}:{MQTT_PORT}")
        client.connect(MQTT_BROKER, MQTT_PORT, MQTT_KEEPALIVE)
        logger.info(f"✅ MQTT: Connected to broker successfully")
        
        topic = f"{MQTT_TOPIC_PREFIX}{username}/notifications"
        message = {
            'type': notification_type,
            'payload': payload
        }
        
        logger.info(f"📤 MQTT: Publishing to topic '{topic}'")
        logger.info(f"📦 MQTT: Message payload: {json.dumps(message)}")
        
        result = client.publish(topic, json.dumps(message))
        
        # Wait for publish to complete (optional for small messages, but safer)
        result.wait_for_publish()
        
        if result.rc == mqtt.MQTT_ERR_SUCCESS:
            logger.info(f"✅ MQTT: Message published successfully to {username} on {topic}")
            return True
        else:
            logger.error(f"❌ MQTT: Publish failed with return code {result.rc} for user {username}")
            return False
            
    except Exception as e:
        logger.error(f"❌ MQTT: Exception during publish - {type(e).__name__}: {str(e)}")
        return False
    finally:
        client.disconnect()
        logger.info(f"🔌 MQTT: Disconnected from broker")

def publish_global_mqtt_notification(notification_type, payload):
    """
    Publishes a notification to the global presence topic.
    Topic format: chess/global/presence
    """
    client = mqtt.Client()
    try:
        client.connect(MQTT_BROKER, MQTT_PORT, MQTT_KEEPALIVE)
        topic = "chess/global/presence"
        message = {
            'type': notification_type,
            'payload': payload
        }
        client.publish(topic, json.dumps(message)).wait_for_publish()
        return True
    except Exception as e:
        logger.error(f"❌ MQTT Global Publish error: {e}")
        return False
    finally:
        client.disconnect()
