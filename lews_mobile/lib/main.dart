import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => AppState(),
      child: const LEWSApp(),
    ),
  );
}

class LEWSApp extends StatelessWidget {
  const LEWSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LEWS Dashboard',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.blueGrey[900],
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: ColorScheme.dark(
          primary: Colors.blueAccent,
          secondary: Colors.tealAccent,
          surface: Colors.grey[850]!,
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}

class AppState extends ChangeNotifier {
  String riskStatus = "UNKNOWN";
  double riskScore = 0.0;
  double moisture = 0.0;
  double accelX = 0.0, accelY = 0.0, accelZ = 0.0;
  bool isConnected = false;

  late MqttServerClient client;

  AppState() {
    _setupMqtt();
  }

  Future<void> _setupMqtt() async {
    // Note: This uses standard TCP on port 1883 for Android/iOS.
    // For Flutter Web, use MqttBrowserClient on WS port 8080/8081.
    client = MqttServerClient('test.mosquitto.org', 'flutter_lews_${DateTime.now().millisecondsSinceEpoch}');
    client.port = 1883;
    client.logging(on: false);
    client.keepAlivePeriod = 20;
    client.onDisconnected = onDisconnected;
    client.onConnected = onConnected;

    final connMess = MqttConnectMessage()
        .withClientIdentifier('flutter_lews_${DateTime.now().millisecondsSinceEpoch}')
        .withWillQos(MqttQos.atLeastOnce);
    client.connectionMessage = connMess;

    try {
      await client.connect();
    } catch (e) {
      print('Exception: $e');
      client.disconnect();
    }

    if (client.connectionStatus!.state == MqttConnectionState.connected) {
      isConnected = true;
      notifyListeners();
      
      client.subscribe('lews/telemetry/live', MqttQos.atMostOnce);
      client.subscribe('lews/telemetry/prediction', MqttQos.atMostOnce);

      client.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
        final recMess = c![0].payload as MqttPublishMessage;
        final payload = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
        final topic = c[0].topic;

        if (topic == 'lews/telemetry/live') {
          _handleLiveTelemetry(payload);
        } else if (topic == 'lews/telemetry/prediction') {
          _handlePrediction(payload);
        }
      });
    }
  }

  void _handleLiveTelemetry(String payload) {
    try {
      final data = jsonDecode(payload);
      moisture = (data['moisture'] ?? data['moisture_percent'] ?? 0).toDouble();
      
      var accel = data['acceleration'];
      if (accel != null) {
        accelX = (accel['x'] ?? 0).toDouble();
        accelY = (accel['y'] ?? 0).toDouble();
        accelZ = (accel['z'] ?? 0).toDouble();
      } else {
        accelX = (data['accel_x'] ?? 0).toDouble();
        accelY = (data['accel_y'] ?? 0).toDouble();
        accelZ = (data['accel_z'] ?? 0).toDouble();
      }
      notifyListeners();
    } catch (e) {
      print("Error parsing telemetry: $e");
    }
  }

  void _handlePrediction(String payload) {
    try {
      final data = jsonDecode(payload);
      riskStatus = data['risk_status'] ?? "UNKNOWN";
      riskScore = (data['risk_score'] ?? 0).toDouble();
      notifyListeners();
    } catch (e) {
      print("Error parsing prediction: $e");
    }
  }

  void publishOverride(Map<String, dynamic> overrides) {
    if (isConnected) {
      final builder = MqttClientPayloadBuilder();
      builder.addString(jsonEncode(overrides));
      client.publishMessage('lews/config/override', MqttQos.atLeastOnce, builder.payload!);
    }
  }

  void onConnected() {
    print('Connected to MQTT');
  }

  void onDisconnected() {
    print('Disconnected from MQTT');
    isConnected = false;
    notifyListeners();
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('LEWS Dashboard'),
        actions: [
          Icon(
            state.isConnected ? Icons.cloud_done : Icons.cloud_off,
            color: state.isConnected ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildAlertBanner(state.riskStatus, state.riskScore),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: _buildMoistureGauge(state.moisture)),
                const SizedBox(width: 16),
                Expanded(child: _buildAccelGauge(state.accelX, state.accelY, state.accelZ)),
              ],
            ),
            const SizedBox(height: 24),
            const GISControlPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertBanner(String status, double score) {
    Color bannerColor = Colors.grey;
    if (status == "SAFE") bannerColor = Colors.green;
    if (status == "WARNING") bannerColor = Colors.orange;
    if (status == "CRITICAL") bannerColor = Colors.red;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bannerColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bannerColor, width: 2),
      ),
      child: Column(
        children: [
          Text(
            'RISK STATUS: $status',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: bannerColor,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'AI Confidence Score: ${score.toStringAsFixed(1)}%',
            style: const TextStyle(fontSize: 16, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildMoistureGauge(double moisture) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text('Soil Moisture', style: TextStyle(fontSize: 18, color: Colors.grey)),
            const SizedBox(height: 16),
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  height: 100,
                  width: 100,
                  child: CircularProgressIndicator(
                    value: moisture / 100,
                    strokeWidth: 10,
                    backgroundColor: Colors.grey[800],
                    color: Colors.blueAccent,
                  ),
                ),
                Text(
                  '${moisture.toStringAsFixed(1)}%',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccelGauge(double x, double y, double z) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text('Vibration (G)', style: TextStyle(fontSize: 18, color: Colors.grey)),
            const SizedBox(height: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBar('X', x, Colors.redAccent),
                const SizedBox(height: 8),
                _buildBar('Y', y, Colors.greenAccent),
                const SizedBox(height: 8),
                _buildBar('Z', z, Colors.blueAccent),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildBar(String axis, double val, Color color) {
    // Normalize roughly -20 to 20 for visual bar
    double normalized = (val.abs() / 20).clamp(0.0, 1.0);
    return Row(
      children: [
        Text('$axis: ', style: const TextStyle(fontWeight: FontWeight.bold, width: 20)),
        Expanded(
          child: LinearProgressIndicator(
            value: normalized,
            backgroundColor: Colors.grey[800],
            color: color,
            minHeight: 12,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(val.toStringAsFixed(1), style: const TextStyle(width: 40, textAlign: TextAlign.right)),
      ],
    );
  }
}

class GISControlPanel extends StatefulWidget {
  const GISControlPanel({super.key});

  @override
  State<GISControlPanel> createState() => _GISControlPanelState();
}

class _GISControlPanelState extends State<GISControlPanel> {
  final _latCtrl = TextEditingController(text: '34.0522');
  final _lngCtrl = TextEditingController(text: '-118.2437');
  final _slopeCtrl = TextEditingController(text: '38.0');
  final _rainCtrl = TextEditingController(text: '110.0');

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('GIS & Environment Override', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _buildTextField('Latitude', _latCtrl)),
                const SizedBox(width: 16),
                Expanded(child: _buildTextField('Longitude', _lngCtrl)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildTextField('Slope (°)', _slopeCtrl)),
                const SizedBox(width: 16),
                Expanded(child: _buildTextField('Rainfall (mm)', _rainCtrl)),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () {
                  final overrides = {
                    'lat': double.tryParse(_latCtrl.text),
                    'lng': double.tryParse(_lngCtrl.text),
                    'slope': double.tryParse(_slopeCtrl.text),
                    'rainfall': double.tryParse(_rainCtrl.text),
                  };
                  context.read<AppState>().publishOverride(overrides);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('GIS Data Synced to AI Backend!'), backgroundColor: Colors.green),
                  );
                },
                icon: const Icon(Icons.sync),
                label: const Text('SYNC OVERRIDES TO AI', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: Colors.grey[900],
      ),
    );
  }
}
