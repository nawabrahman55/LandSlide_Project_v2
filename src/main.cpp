#include <Arduino.h>
#include <Wire.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>
#include <ArduinoJson.h>

// WiFi Configuration
const char* ssid = "Wokwi-GUEST";
const char* password = "";

// MQTT Configuration
const char* mqtt_server = "test.mosquitto.org";
const int mqtt_port = 1883;
const char* mqtt_topic_telemetry = "lews/telemetry/live";

WiFiClient espClient;
PubSubClient client(espClient);

// Sensor Objects
Adafruit_MPU6050 mpu;

// Pin Definitions
#define I2C_SDA 21
#define I2C_SCL 22
#define POT_PIN 34

// Timing
unsigned long lastMsg = 0;
const unsigned long interval = 3000; // 3 seconds

void setup_wifi() {
  delay(10);
  Serial.println();
  Serial.print("Connecting to ");
  Serial.println(ssid);

  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid, password);

  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }

  Serial.println("");
  Serial.println("WiFi connected");
  Serial.println("IP address: ");
  Serial.println(WiFi.localIP());
}

void reconnect() {
  // Loop until we're reconnected
  while (!client.connected()) {
    Serial.print("Attempting MQTT connection...");
    // Create a random client ID
    String clientId = String("LEWS_Node_") + String(random(0xffff), HEX);

    // Attempt to connect
    if (client.connect(clientId.c_str())) {
      Serial.println("connected");
    } else {
      Serial.print("failed, rc=");
      Serial.print(client.state());
      Serial.println(" try again in 5 seconds");
      // Wait 5 seconds before retrying
      delay(5000);
    }
  }
}

void setup() {
  Serial.begin(115200);
  
  setup_wifi();
  
  client.setServer(mqtt_server, mqtt_port);

  // Initialize I2C and MPU6050
  Wire.begin(I2C_SDA, I2C_SCL);
  if (!mpu.begin()) {
    Serial.println("Failed to find MPU6050 chip");
  } else {
    Serial.println("MPU6050 Found!");
    // Configure MPU6050
    mpu.setAccelerometerRange(MPU6050_RANGE_8_G);
    mpu.setGyroRange(MPU6050_RANGE_500_DEG);
    mpu.setFilterBandwidth(MPU6050_BAND_21_HZ);
  }

  // Setup Potentiometer Pin
  pinMode(POT_PIN, INPUT);
}

void loop() {
  if (!client.connected()) {
    reconnect();
  }
  client.loop();

  unsigned long now = millis();
  if (now - lastMsg >= interval) {
    lastMsg = now;

    // Read Potentiometer
    int potValue = analogRead(POT_PIN);
    // Map to moisture percentage 0-100%
    int moisturePercent = map(potValue, 0, 4095, 0, 100);

    // Read MPU6050
    sensors_event_t a, g, temp;
    mpu.getEvent(&a, &g, &temp);

    // Create JSON Payload
    JsonDocument doc;
    doc["moisture_percent"] = moisturePercent;
    
    JsonObject accel = doc["acceleration"].to<JsonObject>();
    accel["x"] = a.acceleration.x;
    accel["y"] = a.acceleration.y;
    accel["z"] = a.acceleration.z;

    char jsonBuffer[256];
    serializeJson(doc, jsonBuffer);

    // Print to Serial
    Serial.print("Publishing message: ");
    Serial.println(jsonBuffer);

    // Publish to MQTT
    client.publish(mqtt_topic_telemetry, jsonBuffer);
  }
}
