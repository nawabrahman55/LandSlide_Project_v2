import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:lews_mobile/main.dart';
import 'package:lews_mobile/services/mqtt_service.dart';

void main() {
  testWidgets('LEWS Dashboard switches dynamically from UNKNOWN to SAFE, WARNING, and CRITICAL', (WidgetTester tester) async {
    // 1. Initialize MqttService without autoConnect to test state transitions deterministically
    final mqttService = MqttService(autoConnect: false);

    await tester.pumpWidget(
      ChangeNotifierProvider<MqttService>.value(
        value: mqttService,
        child: const LEWSApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 2. Initial State Verification: UNKNOWN and Disconnected
    expect(find.text('LEWS Dashboard'), findsOneWidget);
    expect(find.text('UNKNOWN'), findsOneWidget);
    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.text('0.0%'), findsNWidgets(2)); // Initial risk score and moisture

    // 3. Simulate Live Telemetry (Moisture 22.5%, stationary MPU6050)
    final safeTelemetry = {
      'device_id': 'esp32-lews-node',
      'moisture_percent': 22.5,
      'acceleration': {'x': 0.02, 'y': 0.05, 'z': 9.81},
    };
    mqttService.handleIncomingPayload('lews/telemetry/live', jsonEncode(safeTelemetry));
    await tester.pumpAndSettle();

    // Verify live moisture updated
    expect(find.text('22.5%'), findsOneWidget);
    expect(find.text('Dry / Well Drained'), findsOneWidget);

    // 4. Simulate SAFE Prediction
    final safePrediction = {
      'device_id': 'esp32-lews-node',
      'risk_status': 'SAFE',
      'risk_score': 0.0,
      'timestamp': '2026-10-02T11:00:00Z',
    };
    mqttService.handleIncomingPayload('lews/telemetry/prediction', jsonEncode(safePrediction));
    await tester.pumpAndSettle();

    expect(find.text('SAFE'), findsOneWidget);
    expect(find.text('0.0%'), findsOneWidget); // Risk score
    expect(find.text('Ground Slope & Moisture Stable. No Threat Detected.'), findsOneWidget);

    // Verify container background color for SAFE (#2E7D32)
    final safeContainer = tester.widget<Container>(
      find.descendant(
        of: find.byType(AlertBannerCard),
        matching: find.byType(Container).first,
      ),
    );
    final safeDeco = safeContainer.decoration as BoxDecoration;
    expect(safeDeco.color, const Color(0xFF2E7D32));

    // 5. Simulate WARNING Prediction (Monsoon rain / elevated saturation)
    final warnPrediction = {
      'device_id': 'esp32-lews-node',
      'risk_status': 'WARNING',
      'risk_score': 54.5,
      'timestamp': '2026-10-02T11:05:00Z',
    };
    mqttService.handleIncomingPayload('lews/telemetry/prediction', jsonEncode(warnPrediction));
    await tester.pumpAndSettle();

    expect(find.text('WARNING'), findsOneWidget);
    expect(find.text('54.5%'), findsOneWidget);
    expect(find.text('Elevated Moisture or Slope Tremor. Heighten Vigilance.'), findsOneWidget);

    // Verify container background color for WARNING (#F57F17)
    final warnContainer = tester.widget<Container>(
      find.descendant(
        of: find.byType(AlertBannerCard),
        matching: find.byType(Container).first,
      ),
    );
    final warnDeco = warnContainer.decoration as BoxDecoration;
    expect(warnDeco.color, const Color(0xFFF57F17));

    // 6. Simulate CRITICAL Telemetry + Prediction (Ground slip & saturated soil)
    final critTelemetry = {
      'device_id': 'esp32-lews-node',
      'moisture_percent': 92.0,
      'acceleration': {'x': 2.8, 'y': 4.1, 'z': 13.5},
    };
    final critPrediction = {
      'device_id': 'esp32-lews-node',
      'risk_status': 'CRITICAL',
      'risk_score': 100.0,
      'timestamp': '2026-10-02T11:10:00Z',
    };
    mqttService.handleIncomingPayload('lews/telemetry/live', jsonEncode(critTelemetry));
    mqttService.handleIncomingPayload('lews/telemetry/prediction', jsonEncode(critPrediction));
    // Pump animation ticks
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('CRITICAL'), findsOneWidget);
    expect(find.text('100.0%'), findsOneWidget);
    expect(find.text('92.0%'), findsOneWidget); // Moisture
    expect(find.text('Critically Saturated'), findsOneWidget);
    expect(find.text('HIGH LANDSLIDE PROBABILITY / ACTIVE GROUND DISPLACEMENT!'), findsOneWidget);

    // Verify AnimatedBuilder / Pulsing Red (#C62828) container exists in AlertBannerCard
    expect(
      find.descendant(
        of: find.byType(AlertBannerCard),
        matching: find.byType(AnimatedBuilder),
      ),
      findsOneWidget,
    );
  });
}
