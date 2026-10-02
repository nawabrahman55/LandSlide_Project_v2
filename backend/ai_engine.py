"""
Landslide Early Warning System (LEWS) - AI Engine Backend
Subscribes to live ESP32 physical sensor telemetry via EMQX MQTT broker,
evaluates data with the trained RandomForest model and real-time acceleration vector magnitude,
and publishes predictions to lews/telemetry/prediction.
"""

import os
import sys
import json
import time
import math
from datetime import datetime, timezone
import numpy as np
import pandas as pd
import joblib
import paho.mqtt.client as mqtt

# Paths
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_PATH = os.path.join(BASE_DIR, "models", "landslide_rf.joblib")

# MQTT Configuration
MQTT_BROKER = "broker.emqx.io"
MQTT_PORT = 1883
MQTT_KEEPALIVE = 60

# MQTT Topics
TOPIC_LIVE = "lews/telemetry/live"
TOPIC_PRED = "lews/telemetry/prediction"
TOPIC_OVERRIDE = "lews/config/override"

# Contextual GIS & Hydrological Variables (Default baselines, dynamically overridable)
DEFAULT_SLOPE = 30.0      # degrees (NASA SRTM DEM baseline)
DEFAULT_RAINFALL = 15.0   # mm (normal baseline 24h rainfall)
CURRENT_SLOPE = DEFAULT_SLOPE
CURRENT_RAINFALL = DEFAULT_RAINFALL
CURRENT_VEGETATION = 0.4   # NDVI
CURRENT_SOIL_CLAY = 75.0   # % clay content

# Global model holder
rf_pipeline = None


def load_trained_model():
    """
    Loads the serialized RandomForestClassifier pipeline from joblib.
    If the model artifact does not exist, triggers training pipeline.
    """
    global rf_pipeline
    if os.path.exists(MODEL_PATH):
        try:
            print(f"[AI Engine] Loading trained ML model from: {MODEL_PATH}")
            rf_pipeline = joblib.load(MODEL_PATH)
            print("[AI Engine] Model loaded successfully.")
            return rf_pipeline
        except Exception as e:
            print(f"[AI Engine] Failed to load model from {MODEL_PATH}: {e}")
            
    print("[AI Engine] Model artifact not found. Triggering automated model training...")
    from train_model import train_landslide_pipeline
    rf_pipeline = train_landslide_pipeline(output_path=MODEL_PATH)
    return rf_pipeline


def evaluate_telemetry(data: dict) -> dict:
    """
    Evaluates incoming physical sensor telemetry against the trained ML model
    and acceleration vector magnitude to compute risk status and score.
    """
    global rf_pipeline, CURRENT_SLOPE, CURRENT_RAINFALL
    
    if rf_pipeline is None:
        load_trained_model()
        
    device_id = data.get("device_id", "esp32-lews-node")
    
    # Extract live soil moisture
    moisture = float(data.get("moisture_percent", data.get("moisture", 0.0)))
    moisture = max(0.0, min(100.0, moisture))
    
    # Contextual slope and rainfall (supports per-payload override or active defaults)
    slope = float(data.get("slope", CURRENT_SLOPE))
    rainfall = float(data.get("rainfall_24h", data.get("rainfall", CURRENT_RAINFALL)))
    
    # Extract acceleration components (supports both nested 'acceleration' and flat 'accel_*')
    if "acceleration" in data and isinstance(data["acceleration"], dict):
        accel_x = float(data["acceleration"].get("x", 0.0))
        accel_y = float(data["acceleration"].get("y", 0.0))
        accel_z = float(data["acceleration"].get("z", 0.0))
    else:
        accel_x = float(data.get("accel_x", 0.0))
        accel_y = float(data.get("accel_y", 0.0))
        accel_z = float(data.get("accel_z", 0.0))
        
    # Compute total acceleration vector magnitude: |a| = sqrt(x^2 + y^2 + z^2)
    accel_magnitude = math.sqrt(accel_x**2 + accel_y**2 + accel_z**2)
    
    # Determine dynamic vibration / ground shift anomaly
    # If magnitude is near 9.8 m/s^2 (standard gravity), deviation represents dynamic vibration/slip
    if accel_magnitude > 4.0:
        vibration = abs(accel_magnitude - 9.806)
    else:
        # If accelerometer reports in units of g (~1.0g baseline)
        vibration = abs(accel_magnitude - 1.0) * 9.806

    # Prepare ML feature vector
    input_df = pd.DataFrame([{
        "rainfall_24h": rainfall,
        "slope": slope,
        "soil_moisture": moisture
    }])
    
    # Model inference
    try:
        # Predict probability of landslide trigger (class 1)
        probabilities = rf_pipeline.predict_proba(input_df)[0]
        prob_landslide = float(probabilities[1]) if len(probabilities) > 1 else float(probabilities[0])
    except Exception as e:
        print(f"[AI Engine] Prediction error: {e}. Using deterministic heuristic fallback.")
        prob_landslide = 0.5
        
    base_ml_score = prob_landslide * 100.0
    
    # Dynamic kinetic factor from physical vibration/acceleration magnitude
    # Vibration > 0.8 m/s^2 indicates kinetic slope movement or seismic tremors
    if vibration > 0.8:
        kinetic_boost = min(35.0, (vibration - 0.8) * 10.0)
    else:
        kinetic_boost = 0.0
        
    # Combined risk score (0.0 to 100.0%)
    combined_score = round(min(100.0, max(0.0, base_ml_score + kinetic_boost)), 2)
    
    # Context-aware Dynamic AI Thresholding:
    # 1. CRITICAL: High model probability (>=70%) OR active ground slip/severe vibration (vibration >= 2.5 m/s^2)
    # 2. WARNING: Moderate model probability (35-70%) OR notable tremor/tilt (vibration >= 1.2 m/s^2)
    # 3. SAFE: Low moisture, low rain, stable slope, and stationary accelerometer
    if combined_score >= 70.0 or vibration >= 2.8 or prob_landslide >= 0.75:
        risk_status = "CRITICAL"
    elif combined_score >= 35.0 or vibration >= 1.2 or prob_landslide >= 0.35:
        risk_status = "WARNING"
    else:
        risk_status = "SAFE"
        
    timestamp = datetime.now(timezone.utc).isoformat()
    
    result_payload = {
        "device_id": device_id,
        "risk_status": risk_status,
        "risk_score": combined_score,
        "timestamp": timestamp,
        "telemetry": {
            "moisture_percent": round(moisture, 2),
            "accel_x": round(accel_x, 3),
            "accel_y": round(accel_y, 3),
            "accel_z": round(accel_z, 3),
            "accel_magnitude": round(accel_magnitude, 3),
            "vibration": round(vibration, 3),
            "context_slope_deg": round(slope, 1),
            "context_rainfall_mm": round(rainfall, 1)
        }
    }
    
    return result_payload


def on_connect(client, userdata, flags, rc):
    """Callback when client connects to MQTT Broker."""
    if rc == 0:
        print(f"[AI Engine] Successfully connected to EMQX Broker ({MQTT_BROKER}:{MQTT_PORT})")
        client.subscribe(TOPIC_LIVE)
        client.subscribe(TOPIC_OVERRIDE)
        print(f"[AI Engine] Subscribed to topics: '{TOPIC_LIVE}' and '{TOPIC_OVERRIDE}'")
    else:
        print(f"[AI Engine] Connection to EMQX broker failed with code: {rc}")


def on_message(client, userdata, msg):
    """Callback when an MQTT message is received."""
    global CURRENT_SLOPE, CURRENT_RAINFALL, CURRENT_VEGETATION, CURRENT_SOIL_CLAY
    try:
        payload_str = msg.payload.decode("utf-8")
        data = json.loads(payload_str)
        
        # Handle GIS / Hydrological parameter overrides
        if msg.topic == TOPIC_OVERRIDE:
            print(f"\n[GIS OVERRIDE] Received geographic parameter updates:")
            if "slope" in data:
                CURRENT_SLOPE = float(data["slope"])
            if "rainfall" in data:
                CURRENT_RAINFALL = float(data["rainfall"])
            if "vegetation" in data:
                CURRENT_VEGETATION = float(data["vegetation"])
            if "soil_clay" in data:
                CURRENT_SOIL_CLAY = float(data["soil_clay"])
            print(f" -> Active Context: Slope={CURRENT_SLOPE}°, 24h Rain={CURRENT_RAINFALL}mm")
            return

        # Process Live Physical Sensor Telemetry
        result = evaluate_telemetry(data)
        
        # Format JSON publication
        pred_json = json.dumps({
            "device_id": result["device_id"],
            "risk_status": result["risk_status"],
            "risk_score": result["risk_score"],
            "timestamp": result["timestamp"]
        })
        
        client.publish(TOPIC_PRED, pred_json)
        
        t = result["telemetry"]
        print(f"\n[TELEMETRY PROCESSED] Device: {result['device_id']}")
        print(f"  Moisture: {t['moisture_percent']}% | Accel Magnitude: {t['accel_magnitude']:.2f} m/s^2 (Vib: {t['vibration']:.2f} m/s^2)")
        print(f"  Context:  Slope {t['context_slope_deg']}° | 24h Rain: {t['context_rainfall_mm']} mm")
        print(f"  -> PREDICTION PUBLISHED: Status={result['risk_status']}, Score={result['risk_score']}%, Time={result['timestamp']}")
        
    except Exception as e:
        print(f"[AI Engine] Error processing message on topic {msg.topic}: {e}")


def main():
    """Main execution loop for LEWS AI Engine."""
    print("=" * 65)
    print("LEWS AI Engine Backend - Real-Data ML Telemetry Pipeline")
    print(f"Target Broker: {MQTT_BROKER}:{MQTT_PORT}")
    print("=" * 65)
    
    # Load or initialize model
    load_trained_model()
    
    client_id = f"lews_ai_backend_{int(time.time())}"
    client = mqtt.Client(client_id=client_id)
    client.on_connect = on_connect
    client.on_message = on_message
    
    while True:
        try:
            print(f"[AI Engine] Connecting to EMQX broker at {MQTT_BROKER}:{MQTT_PORT}...")
            client.connect(MQTT_BROKER, MQTT_PORT, MQTT_KEEPALIVE)
            print("[AI Engine] Entering MQTT listener loop...")
            client.loop_forever()
        except KeyboardInterrupt:
            print("\n[AI Engine] Terminating by user request...")
            client.disconnect()
            break
        except Exception as e:
            print(f"[AI Engine] MQTT connection exception: {e}")
            print("[AI Engine] Retrying in 5 seconds...")
            time.sleep(5)


if __name__ == "__main__":
    main()
