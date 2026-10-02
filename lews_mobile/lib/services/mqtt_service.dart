import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:uuid/uuid.dart';

enum MqttConnectionStatus {
  connecting,
  connected,
  disconnected,
}

/// Service managing the WebSocket-based MQTT connection to EMQX broker
/// and handling incoming telemetry and prediction streams.
class MqttService extends ChangeNotifier {
  static const String brokerHost = 'broker.emqx.io';
  static const int brokerPort = 8083;
  static const String topicTelemetryLive = 'lews/telemetry/live';
  static const String topicPrediction = 'lews/telemetry/prediction';
  static const String topicOverride = 'lews/config/override';

  late MqttServerClient client;
  final String clientId = 'flutter_lews_${const Uuid().v4().substring(0, 8)}';

  // Observable state fields
  MqttConnectionStatus _connectionStatus = MqttConnectionStatus.disconnected;
  String _connectionStateString = 'Disconnected';

  double _moisturePercent = 0.0;
  double _accelX = 0.0;
  double _accelY = 0.0;
  double _accelZ = 0.0;
  String _riskStatus = 'UNKNOWN';
  double _riskScore = 0.0;
  String _lastTimestamp = '';

  // StreamControllers for stream-based consumers
  final _moistureController = StreamController<double>.broadcast();
  final _accelController = StreamController<Map<String, double>>.broadcast();
  final _riskStatusController = StreamController<String>.broadcast();
  final _riskScoreController = StreamController<double>.broadcast();

  // Getters for ChangeNotifier consumer
  MqttConnectionStatus get connectionStatus => _connectionStatus;
  String get connectionStateString => _connectionStateString;
  bool get isConnected => _connectionStatus == MqttConnectionStatus.connected;

  double get moisturePercent => _moisturePercent;
  double get accelX => _accelX;
  double get accelY => _accelY;
  double get accelZ => _accelZ;
  String get riskStatus => _riskStatus;
  double get riskScore => _riskScore;
  String get lastTimestamp => _lastTimestamp;

  // Stream getters
  Stream<double> get moistureStream => _moistureController.stream;
  Stream<Map<String, double>> get accelStream => _accelController.stream;
  Stream<String> get riskStatusStream => _riskStatusController.stream;
  Stream<double> get riskScoreStream => _riskScoreController.stream;

  MqttService({bool autoConnect = true}) {
    _initClient();
    if (autoConnect) {
      connect();
    }
  }

  void _initClient() {
    // 1. Initialize MqttServerClient with broker, client identifier, and WebSocket port 8083
    client = MqttServerClient.withPort(brokerHost, clientId, brokerPort);

    // 2. Configure WebSocket transport & protocols
    client.useWebSocket = true;
    client.port = brokerPort;
    client.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
    if (!client.server.startsWith('ws://') && !client.server.startsWith('wss://')) {
      client.server = 'ws://${client.server}';
    }
    if (!client.server.endsWith('/mqtt')) {
      client.server = '${client.server}/mqtt';
    }

    // 3. Keep-alive, auto-reconnect, and logging
    client.keepAlivePeriod = 30;
    client.autoReconnect = true;
    client.logging(on: true);

    // Callbacks
    client.onConnected = _onConnected;
    client.onDisconnected = _onDisconnected;
    client.onAutoReconnected = _onAutoReconnected;
    client.onAutoReconnect = _onAutoReconnect;

    final connMess = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .withWillQos(MqttQos.atLeastOnce);
    client.connectionMessage = connMess;
  }

  /// Connects to the EMQX MQTT broker over WebSockets
  Future<void> connect() async {
    if (_connectionStatus == MqttConnectionStatus.connected) return;

    _updateStatus(MqttConnectionStatus.connecting, 'Connecting...');

    try {
      debugPrint('[MqttService] Connecting to $brokerHost:$brokerPort as $clientId via WebSocket...');
      await client.connect();
    } catch (e) {
      debugPrint('[MqttService] Connection exception: $e');
      _updateStatus(MqttConnectionStatus.disconnected, 'Disconnected');
      return;
    }

    if (client.connectionStatus?.state == MqttConnectionState.connected) {
      _updateStatus(MqttConnectionStatus.connected, 'Connected to EMQX');
      _subscribeToTopics();
    } else {
      debugPrint('[MqttService] Failed to connect: ${client.connectionStatus?.state}');
      _updateStatus(MqttConnectionStatus.disconnected, 'Disconnected');
    }
  }

  void _subscribeToTopics() {
    debugPrint('[MqttService] Subscribing to telemetry topics...');
    client.subscribe(topicTelemetryLive, MqttQos.atMostOnce);
    client.subscribe(topicPrediction, MqttQos.atMostOnce);

    client.updates?.listen(_handleIncomingMessages);
  }

  void _handleIncomingMessages(List<MqttReceivedMessage<MqttMessage?>>? messages) {
    if (messages == null || messages.isEmpty) return;

    final recMess = messages[0].payload as MqttPublishMessage;
    final payloadString = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
    final topic = messages[0].topic;

    debugPrint('[MqttService] Incoming on [$topic]: $payloadString');
    handleIncomingPayload(topic, payloadString);
  }

  /// Parses and processes an incoming payload string. Visible for automated testing.
  @visibleForTesting
  void handleIncomingPayload(String topic, String payloadString) {
    try {
      final dynamic decoded = jsonDecode(payloadString);
      if (decoded is! Map<String, dynamic>) {
        debugPrint('[MqttService] Warning: Payload is not a JSON object: $payloadString');
        return;
      }

      if (topic == topicTelemetryLive) {
        _parseLiveTelemetry(decoded);
      } else if (topic == topicPrediction) {
        _parsePrediction(decoded);
      }
    } catch (e, stack) {
      debugPrint('[MqttService] Error parsing incoming message: $e\n$stack');
    }
  }

  void _parseLiveTelemetry(Map<String, dynamic> data) {
    // 1. Parse moisture_percent (supports both moisture_percent and moisture)
    if (data.containsKey('moisture_percent')) {
      _moisturePercent = (data['moisture_percent'] as num).toDouble();
    } else if (data.containsKey('moisture')) {
      _moisturePercent = (data['moisture'] as num).toDouble();
    }
    _moistureController.add(_moisturePercent);

    // 2. Parse accel_x, accel_y, accel_z (supports nested acceleration or flat accel_*)
    if (data['acceleration'] is Map<String, dynamic>) {
      final accel = data['acceleration'] as Map<String, dynamic>;
      _accelX = (accel['x'] as num? ?? 0.0).toDouble();
      _accelY = (accel['y'] as num? ?? 0.0).toDouble();
      _accelZ = (accel['z'] as num? ?? 0.0).toDouble();
    } else {
      _accelX = (data['accel_x'] as num? ?? 0.0).toDouble();
      _accelY = (data['accel_y'] as num? ?? 0.0).toDouble();
      _accelZ = (data['accel_z'] as num? ?? 0.0).toDouble();
    }
    _accelController.add({'x': _accelX, 'y': _accelY, 'z': _accelZ});

    notifyListeners();
  }

  void _parsePrediction(Map<String, dynamic> data) {
    // 1. Parse risk_status (SAFE, WARNING, CRITICAL)
    if (data.containsKey('risk_status')) {
      _riskStatus = data['risk_status'].toString().toUpperCase();
      _riskStatusController.add(_riskStatus);
    }

    // 2. Parse risk_score (0.0 to 100.0)
    if (data.containsKey('risk_score')) {
      _riskScore = (data['risk_score'] as num).toDouble();
      _riskScoreController.add(_riskScore);
    }

    // 3. Optional timestamp
    if (data.containsKey('timestamp')) {
      _lastTimestamp = data['timestamp'].toString();
    }

    notifyListeners();
  }

  /// Publishes GIS / Environmental parameters override to lews/config/override
  void publishOverride(Map<String, dynamic> overrides) {
    if (!isConnected) {
      debugPrint('[MqttService] Cannot publish override: Not connected to MQTT broker.');
      return;
    }

    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode(overrides));
    client.publishMessage(topicOverride, MqttQos.atLeastOnce, builder.payload!);
    debugPrint('[MqttService] Published override to $topicOverride: $overrides');
  }

  void _onConnected() {
    debugPrint('[MqttService] Connected successfully to EMQX WebSocket broker.');
    _updateStatus(MqttConnectionStatus.connected, 'Connected to EMQX');
  }

  void _onDisconnected() {
    debugPrint('[MqttService] Disconnected from EMQX broker.');
    _updateStatus(MqttConnectionStatus.disconnected, 'Disconnected');
  }

  void _onAutoReconnect() {
    debugPrint('[MqttService] Auto-reconnecting to EMQX broker...');
    _updateStatus(MqttConnectionStatus.connecting, 'Connecting...');
  }

  void _onAutoReconnected() {
    debugPrint('[MqttService] Auto-reconnected to EMQX broker.');
    _updateStatus(MqttConnectionStatus.connected, 'Connected to EMQX');
    _subscribeToTopics();
  }

  void _updateStatus(MqttConnectionStatus status, String stateString) {
    _connectionStatus = status;
    _connectionStateString = stateString;
    notifyListeners();
  }

  @override
  void dispose() {
    client.disconnect();
    _moistureController.close();
    _accelController.close();
    _riskStatusController.close();
    _riskScoreController.close();
    super.dispose();
  }
}
