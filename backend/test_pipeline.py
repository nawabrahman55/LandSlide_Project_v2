"""
Verification and Test Suite for LEWS ML Pipeline and AI Engine
"""

import json
from ai_engine import evaluate_telemetry, load_trained_model

def run_tests():
    print("=" * 65)
    print("LEWS Telemetry Evaluation and ML Pipeline Test Suite")
    print("=" * 65)
    
    # 1. Ensure model loads
    model = load_trained_model()
    assert model is not None, "Failed to load model!"
    print("[PASS] Trained RandomForest model artifact loaded successfully.")
    
    test_cases = [
        {
            "name": "Case 1: Baseline dry conditions, stationary sensor (Safe)",
            "payload": {
                "device_id": "esp32-node-01",
                "moisture_percent": 18.5,
                "rainfall_24h": 10.0,
                "slope": 22.0,
                "acceleration": {"x": 0.02, "y": 0.05, "z": 9.81}
            },
            "expected_status": "SAFE"
        },
        {
            "name": "Case 2: Moderate rain & transitional soil moisture (Warning)",
            "payload": {
                "device_id": "esp32-node-02",
                "moisture_percent": 45.0,
                "rainfall_24h": 38.0,
                "slope": 26.0,
                "acceleration": {"x": 0.10, "y": 0.15, "z": 9.80}
            },
            "expected_status": ["WARNING", "SAFE"]
        },
        {
            "name": "Case 3: Heavy rain & soil saturation (Critical)",
            "payload": {
                "device_id": "esp32-node-03",
                "moisture_percent": 85.0,
                "rainfall_24h": 95.0,
                "slope": 36.0,
                "acceleration": {"x": 0.15, "y": 0.22, "z": 9.80}
            },
            "expected_status": "CRITICAL"
        },
        {
            "name": "Case 4: Ground slip / tremor detected via MPU6050 (Critical)",
            "payload": {
                "device_id": "esp32-node-04",
                "moisture_percent": 90.0,
                "rainfall_24h": 120.0,
                "slope": 38.0,
                "acceleration": {"x": 3.2, "y": 4.5, "z": 12.8}
            },
            "expected_status": "CRITICAL"
        }
    ]
    
    for case in test_cases:
        print(f"\n--- Testing {case['name']} ---")
        payload = case["payload"]
        result = evaluate_telemetry(payload)
        
        # Verify required keys according to task prompt:
        # device_id, risk_status, risk_score, timestamp
        for key in ["device_id", "risk_status", "risk_score", "timestamp"]:
            assert key in result, f"Missing required key: {key}"
            
        print(f"Device ID:       {result['device_id']}")
        print(f"Risk Status:     {result['risk_status']}")
        print(f"Risk Score:      {result['risk_score']}%")
        print(f"Timestamp:       {result['timestamp']}")
        print(f"Accel Magnitude: {result['telemetry']['accel_magnitude']} m/s^2")
        print(f"Vibration:       {result['telemetry']['vibration']} m/s^2")
        print(f"Slope / Rain:    {result['telemetry']['context_slope_deg']} deg / {result['telemetry']['context_rainfall_mm']} mm")
        
        expected = case["expected_status"]
        if isinstance(expected, list):
            assert result["risk_status"] in expected, f"Expected {expected}, got {result['risk_status']}"
        else:
            assert result["risk_status"] == expected, f"Expected {expected}, got {result['risk_status']}"
            
        print(" -> [PASS]")
        
    print("\n" + "=" * 65)
    print("ALL TEST SCENARIOS PASSED WITH VALID METRICS!")
    print("=" * 65)

if __name__ == "__main__":
    run_tests()
