# MASTER PROJECT CONTEXT: Landslide Early Warning System (LEWS)
## For AI Agent (Google Anti-Gravity IDE)

**CRITICAL SYSTEM DIRECTIVE:** 
Do NOT modify, overwrite, or suggest changes to `diagram.json`. The user has manually configured the hardware wiring in Wokwi (ESP32, MPU6050, and Potentiometer). The hardware layout is LOCKED. Do not attempt to add an OLED display or alter the I2C/Analog pins.

---

### 1. Project Architecture & Stack
*   **Environment:** Google Anti-Gravity IDE (PlatformIO for firmware, Python for Backend, Flutter for Mobile).
*   **Compliance:** 100% FLOSS & Open Source Hardware. No proprietary APIs.
*   **Goal:** Build a context-aware Dynamic AI Thresholding system for landslide prediction.

### 2. Phase 1: Edge Node Firmware (C++ / PlatformIO)
*   **Hardware:** Simulated ESP32.
*   **Sensors:** 
    *   MPU6050 (Vibration/Tilt): Connected via I2C (SDA = GPIO 21, SCL = GPIO 22).
    *   Potentiometer (Simulating Capacitive Soil Moisture): Connected via Analog (SIG = GPIO 34).
*   **Task:** Write `src/main.cpp`. 
*   **Functionality:**
    1. Connect to `Wokwi-GUEST` WiFi.
    2. Read MPU6050 (Acceleration X, Y, Z).
    3. Read Potentiometer (Map analog 0-4095 to 0-100% moisture).
    4. Connect to MQTT broker (`broker.hivemq.com`).
    5. Publish a JSON payload to `lews/telemetry/live` every 3 seconds.
    6. *Do not write code for an OLED screen.*

### 3. Phase 2: Python AI Backend
*   **Data Sources:**
    *   Live Telemetry: Ground Vibration & Tilt (MPU6050), Soil Saturation (Simulated).
    *   Static GIS: Slope (NASA SRTM DEM), Land Cover (ISRO Bhuvan/Copernicus LULC), Infrastructure (OSM), Soil Type (ISRIC SoilGrids / ISRO Bhuvan).
    *   Hydrological: Antecedent Rainfall (IMD/NASA GPM Historical).
*   **Task:** Create a Python script that subscribes to `lews/telemetry/live`.
*   **Logic:** Merge live telemetry with mocked open-source GIS/Hydrological data. Feed this combined data array into a Scikit-Learn Random Forest model (mock the model training for now to return a Risk Status: Safe, Warning, or Critical). Publish the prediction to `lews/telemetry/prediction`.

### 4. Phase 3: Android Application (Flutter)
*   **Task:** Generate a Flutter application.
*   **Functionality:** 
    1. Connect to the same MQTT broker (`broker.hivemq.com`).
    2. Display a real-time dashboard of the ESP32 sensor telemetry.
    3. Display the AI Risk Status (Safe/Warning/Critical) from the backend.
    4. Include a UI section to input/update GPS coordinates (to simulate fetching new geographic data).
