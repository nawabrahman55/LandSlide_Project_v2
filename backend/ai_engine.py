import json
import time
import math
from datetime import datetime
import numpy as np
import paho.mqtt.client as mqtt
from sklearn.ensemble import RandomForestClassifier

# MQTT Configuration
MQTT_BROKER = "test.mosquitto.org"
MQTT_PORT = 1883
TOPIC_LIVE = "lews/telemetry/live"
TOPIC_PRED = "lews/telemetry/prediction"
TOPIC_OVERRIDE = "lews/config/override"

# Mock Static GIS & Hydrological Data
MOCK_SLOPE = 38.0  # degrees
MOCK_SOIL_CLAY = 75.0  # % (High Clay)
MOCK_RAINFALL = 110.0  # mm (past 3 days)
MOCK_VEGETATION = 0.4  # NDVI (0-1, where lower means less vegetation/higher risk)
MOCK_INFRASTRUCTURE_DIST = 15.0  # meters from nearest road

# Initialize and train a basic Random Forest Model
# Features: [Moisture, Vibration_Magnitude, Slope, Vegetation, Infra_Dist, Soil_Clay, Rainfall]
print("Initializing and training Random Forest model...")
rf_model = RandomForestClassifier(n_estimators=10, random_state=42)

# Mock training data to create decision boundaries
# Safe: low moisture, low accel, mild slope
# Warning: high moisture OR high accel
# Critical: high moisture AND high accel AND steep slope
X_train = np.array([
    [20.0, 0.1, 20.0, 0.8, 50.0, 30.0, 10.0],  # Safe
    [40.0, 0.2, 38.0, 0.6, 20.0, 75.0, 50.0],  # Safe
    [80.0, 0.5, 38.0, 0.4, 15.0, 75.0, 110.0], # Warning
    [60.0, 2.0, 38.0, 0.3, 10.0, 75.0, 110.0], # Warning
    [90.0, 5.0, 38.0, 0.2, 5.0, 75.0, 110.0],  # Critical
    [95.0, 8.0, 38.0, 0.1, 2.0, 75.0, 110.0]   # Critical
])
y_train = np.array([0, 0, 1, 1, 2, 2]) # 0: SAFE, 1: WARNING, 2: CRITICAL
rf_model.fit(X_train, y_train)
risk_labels = {0: "SAFE", 1: "WARNING", 2: "CRITICAL"}
print("Model training complete.")

def on_connect(client, userdata, flags, rc):
    print(f"Connected to MQTT Broker with result code {rc}")
    client.subscribe(TOPIC_LIVE)
    client.subscribe(TOPIC_OVERRIDE)
    print(f"Subscribed to topics: {TOPIC_LIVE} and {TOPIC_OVERRIDE}")

def on_message(client, userdata, msg):
    global MOCK_SLOPE, MOCK_VEGETATION, MOCK_INFRASTRUCTURE_DIST, MOCK_SOIL_CLAY, MOCK_RAINFALL
    try:
        payload = msg.payload.decode('utf-8')
        data = json.loads(payload)
        
        if msg.topic == TOPIC_OVERRIDE:
            print(f"\n[GIS OVERRIDE RECEIVED] Updating AI variables...")
            if "slope" in data: MOCK_SLOPE = float(data["slope"])
            if "rainfall" in data: MOCK_RAINFALL = float(data["rainfall"])
            if "vegetation" in data: MOCK_VEGETATION = float(data["vegetation"])
            if "infra_dist" in data: MOCK_INFRASTRUCTURE_DIST = float(data["infra_dist"])
            if "soil_clay" in data: MOCK_SOIL_CLAY = float(data["soil_clay"])
            print(f" -> New Values: Slope={MOCK_SLOPE}°, Rain={MOCK_RAINFALL}mm, Veg={MOCK_VEGETATION}, Infra={MOCK_INFRASTRUCTURE_DIST}m, Clay={MOCK_SOIL_CLAY}%")
            return

        # Process Live Telemetry
        device_id = data.get("device_id", "esp32-1")
        
        moisture = data.get("moisture", data.get("moisture_percent", 0))
        
        accel_x = data.get("accel_x", 0.0)
        accel_y = data.get("accel_y", 0.0)
        accel_z = data.get("accel_z", 0.0)
        
        # Phase 1 nested format fallback
        if "acceleration" in data:
            accel_x = data["acceleration"].get("x", accel_x)
            accel_y = data["acceleration"].get("y", accel_y)
            accel_z = data["acceleration"].get("z", accel_z)
            
        accel_magnitude = math.sqrt(accel_x**2 + accel_y**2 + accel_z**2)
        # Normalize baseline gravity (approx 9.8 m/s^2) for vibration heuristic
        vibration = abs(accel_magnitude - 9.8) if accel_magnitude > 5 else accel_magnitude

        print(f"\n[TELEMETRY RECEIVED] Device: {device_id}")
        print(f" 1. Live Soil Moisture: {moisture}%")
        print(f" 2. Live Vibration:     ({accel_x:.2f}, {accel_y:.2f}, {accel_z:.2f}) -> {vibration:.2f}g")
        print(f" 3. Mocked Topography:  {MOCK_SLOPE}° Slope")
        print(f" 4. Mocked Vegetation:  {MOCK_VEGETATION} NDVI")
        print(f" 5. Mocked Infra Dist:  {MOCK_INFRASTRUCTURE_DIST}m")
        print(f" 6. Mocked Soil Type:   {MOCK_SOIL_CLAY}% Clay")
        print(f" 7. Mocked Rainfall:    {MOCK_RAINFALL}mm (past 3 days)")
        
        # Feature vector for prediction
        features = np.array([[moisture, vibration, MOCK_SLOPE, MOCK_VEGETATION, MOCK_INFRASTRUCTURE_DIST, MOCK_SOIL_CLAY, MOCK_RAINFALL]])
        
        # Predict
        prediction_idx = rf_model.predict(features)[0]
        risk_status = risk_labels[prediction_idx]
        
        # Calculate a mock risk score based on predict_proba
        probabilities = rf_model.predict_proba(features)[0]
        risk_score = round(probabilities[prediction_idx] * 100, 2)
        
        # Publish Result
        result_payload = {
            "device_id": device_id,
            "risk_status": risk_status,
            "risk_score": risk_score,
            "timestamp": datetime.utcnow().isoformat() + "Z"
        }
        
        result_json = json.dumps(result_payload)
        client.publish(TOPIC_PRED, result_json)
        print(f"[PREDICTION PUBLISHED] {result_json}")

    except Exception as e:
        print(f"Error processing message: {e}")

# Note: Using API v1 callback signature as standard. If using paho-mqtt v2, 
# it requires CallbackAPIVersion, so we'll check compatibility or just use v1 style.
client = mqtt.Client()
client.on_connect = on_connect
client.on_message = on_message

try:
    while True:
        try:
            print("Connecting to broker...")
            client.connect(MQTT_BROKER, MQTT_PORT, 60)
            client.loop_forever()
        except Exception as e:
            print(f"Connection failed: {e}. Retrying in 5 seconds...")
            time.sleep(5)
except KeyboardInterrupt:
    print("Exiting...")
    client.disconnect()
