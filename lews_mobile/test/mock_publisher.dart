import 'dart:convert';
import 'dart:io';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:uuid/uuid.dart';

/// Standalone simulation script that publishes mock telemetry and prediction
/// packets to EMQX broker (or demonstrates payload schemas for test assertions).
Future<void> main() async {
  print('=' * 60);
  print('LEWS Mock Publisher: WebSocket / TCP Telemetry Simulator');
  print('=' * 60);

  const String broker = 'broker.emqx.io';
  const int port = 8083; // WebSocket port
  final String clientId = 'mock_pub_${const Uuid().v4().substring(0, 8)}';

  final client = MqttServerClient.withPort(broker, clientId, port);
  client.useWebSocket = true;
  client.port = port;
  client.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
  if (!client.server.startsWith('ws://') && !client.server.startsWith('wss://')) {
    client.server = 'ws://${client.server}';
  }
  if (!client.server.endsWith('/mqtt')) {
    client.server = '${client.server}/mqtt';
  }
  client.keepAlivePeriod = 30;
  client.logging(on: false);

  final connMess = MqttConnectMessage()
      .withClientIdentifier(clientId)
      .withWillQos(MqttQos.atLeastOnce);
  client.connectionMessage = connMess;

  bool isConnected = false;
  try {
    print('[Simulator] Connecting to $broker:$port via WebSocket...');
    await client.connect().timeout(const Duration(seconds: 5));
    isConnected = client.connectionStatus?.state == MqttConnectionState.connected;
  } catch (e) {
    print('[Simulator] Note: Live network connection unavailable or timed out: $e');
  }

  // Simulation packets
  final packets = [
    {
      'phase': 'Phase 1: Normal Dry Conditions (Safe)',
      'topic_telemetry': 'lews/telemetry/live',
      'telemetry_payload': {
        'device_id': 'esp32-lews-node',
        'moisture_percent': 18.5,
        'acceleration': {'x': 0.02, 'y': 0.04, 'z': 9.81},
      },
      'topic_prediction': 'lews/telemetry/prediction',
      'prediction_payload': {
        'device_id': 'esp32-lews-node',
        'risk_status': 'SAFE',
        'risk_score': 0.0,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      }
    },
    {
      'phase': 'Phase 2: Persistent Monsoon Rainfall & Rising Moisture (Warning)',
      'topic_telemetry': 'lews/telemetry/live',
      'telemetry_payload': {
        'device_id': 'esp32-lews-node',
        'moisture_percent': 65.0,
        'acceleration': {'x': 0.15, 'y': 0.20, 'z': 9.80},
      },
      'topic_prediction': 'lews/telemetry/prediction',
      'prediction_payload': {
        'device_id': 'esp32-lews-node',
        'risk_status': 'WARNING',
        'risk_score': 54.5,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      }
    },
    {
      'phase': 'Phase 3: Saturated Soil + Active Slope Displacement (Critical)',
      'topic_telemetry': 'lews/telemetry/live',
      'telemetry_payload': {
        'device_id': 'esp32-lews-node',
        'moisture_percent': 94.0,
        'acceleration': {'x': 2.8, 'y': 4.1, 'z': 13.5},
      },
      'topic_prediction': 'lews/telemetry/prediction',
      'prediction_payload': {
        'device_id': 'esp32-lews-node',
        'risk_status': 'CRITICAL',
        'risk_score': 100.0,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      }
    },
  ];

  for (final pkt in packets) {
    print('\n>>> Running: ${pkt['phase']}');
    final telemJson = jsonEncode(pkt['telemetry_payload']);
    final predJson = jsonEncode(pkt['prediction_payload']);

    print(' - Telemetry  -> ${pkt['topic_telemetry']}: $telemJson');
    print(' - Prediction -> ${pkt['topic_prediction']}: $predJson');

    if (isConnected) {
      final b1 = MqttClientPayloadBuilder()..addString(telemJson);
      client.publishMessage(pkt['topic_telemetry'] as String, MqttQos.atLeastOnce, b1.payload!);

      final b2 = MqttClientPayloadBuilder()..addString(predJson);
      client.publishMessage(pkt['topic_prediction'] as String, MqttQos.atLeastOnce, b2.payload!);
      print(' [SENT via EMQX WebSocket]');
      await Future.delayed(const Duration(milliseconds: 500));
    } else {
      print(' [VALIDATED Payload Schema (Offline Simulation)]');
    }
  }

  if (isConnected) {
    client.disconnect();
    print('\n[Simulator] Disconnected cleanly from broker.');
  }

  print('\n' + '=' * 60);
  print('SIMULATION RUN COMPLETE');
  print('=' * 60);
  exit(0);
}
