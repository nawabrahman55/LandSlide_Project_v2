import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/mqtt_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => MqttService(),
      child: const LEWSApp(),
    ),
  );
}

class LEWSApp extends StatelessWidget {
  const LEWSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LEWS Early Warning Dashboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F141C),
        primaryColor: const Color(0xFF1E293B),
        cardColor: const Color(0xFF1B2332),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF38BDF8),
          secondary: const Color(0xFF34D399),
          surface: const Color(0xFF1B2332),
          error: const Color(0xFFEF4444),
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final mqtt = context.watch<MqttService>();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF161E2E),
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.terrain_rounded, color: Color(0xFF38BDF8), size: 26),
            const SizedBox(width: 10),
            Text(
              'LEWS Dashboard',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14.0),
            child: Center(
              child: _buildConnectionChip(context, mqtt),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Status Alert Card
            AlertBannerCard(
              status: mqtt.riskStatus,
              score: mqtt.riskScore,
              lastUpdated: mqtt.lastTimestamp,
            ),
            const SizedBox(height: 20),

            // Live Telemetry Cards: Soil Moisture & IMU Acceleration
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: MoistureGaugeCard(moisture: mqtt.moisturePercent),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: AccelerationGaugeCard(
                    accelX: mqtt.accelX,
                    accelY: mqtt.accelY,
                    accelZ: mqtt.accelZ,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // GIS and Environmental Override Panel
            const GISControlPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionChip(BuildContext context, MqttService mqtt) {
    Color chipBg;
    Color borderCol;
    Color textCol;
    IconData icon;

    switch (mqtt.connectionStatus) {
      case MqttConnectionStatus.connected:
        chipBg = const Color(0xFF14532D).withValues(alpha: 0.6);
        borderCol = const Color(0xFF22C55E);
        textCol = const Color(0xFF86EFAC);
        icon = Icons.cloud_done_rounded;
        break;
      case MqttConnectionStatus.connecting:
        chipBg = const Color(0xFF78350F).withValues(alpha: 0.6);
        borderCol = const Color(0xFFF59E0B);
        textCol = const Color(0xFFFDE68A);
        icon = Icons.sync_rounded;
        break;
      case MqttConnectionStatus.disconnected:
        chipBg = const Color(0xFF7F1D1D).withValues(alpha: 0.6);
        borderCol = const Color(0xFFEF4444);
        textCol = const Color(0xFFFCA5A5);
        icon = Icons.cloud_off_rounded;
        break;
    }

    return InkWell(
      onTap: () {
        if (!mqtt.isConnected) {
          mqtt.connect();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Reconnecting to EMQX WebSocket broker...'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: chipBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderCol, width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: textCol),
            const SizedBox(width: 6),
            Text(
              mqtt.connectionStateString,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: textCol,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dynamic Alert Banner with pulsing animation for CRITICAL risk
class AlertBannerCard extends StatefulWidget {
  final String status;
  final double score;
  final String lastUpdated;

  const AlertBannerCard({
    super.key,
    required this.status,
    required this.score,
    required this.lastUpdated,
  });

  @override
  State<AlertBannerCard> createState() => _AlertBannerCardState();
}

class _AlertBannerCardState extends State<AlertBannerCard> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _glowAnimation = Tween<double>(begin: 0.65, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _updateAnimationState();
  }

  @override
  void didUpdateWidget(covariant AlertBannerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      _updateAnimationState();
    }
  }

  void _updateAnimationState() {
    if (widget.status.toUpperCase() == 'CRITICAL') {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      if (_pulseController.isAnimating) {
        _pulseController.stop();
        _pulseController.reset();
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusUpper = widget.status.toUpperCase();

    // Required color mapping:
    // 'SAFE' -> Green background (#2E7D32)
    // 'WARNING' -> Amber background (#F57F17)
    // 'CRITICAL' -> Pulsing Red background (#C62828)
    Color baseBg;
    Color accentBorder;
    IconData statusIcon;
    String statusSubtitle;

    switch (statusUpper) {
      case 'SAFE':
        baseBg = const Color(0xFF2E7D32);
        accentBorder = const Color(0xFF4CAF50);
        statusIcon = Icons.check_circle_rounded;
        statusSubtitle = 'Ground Slope & Moisture Stable. No Threat Detected.';
        break;
      case 'WARNING':
        baseBg = const Color(0xFFF57F17);
        accentBorder = const Color(0xFFFFB300);
        statusIcon = Icons.warning_amber_rounded;
        statusSubtitle = 'Elevated Moisture or Slope Tremor. Heighten Vigilance.';
        break;
      case 'CRITICAL':
        baseBg = const Color(0xFFC62828);
        accentBorder = const Color(0xFFFF5252);
        statusIcon = Icons.dangerous_rounded;
        statusSubtitle = 'HIGH LANDSLIDE PROBABILITY / ACTIVE GROUND DISPLACEMENT!';
        break;
      default:
        baseBg = const Color(0xFF334155);
        accentBorder = const Color(0xFF64748B);
        statusIcon = Icons.sensors_off_rounded;
        statusSubtitle = 'Awaiting Telemetry & AI Prediction Stream...';
        break;
    }

    Widget content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: BoxDecoration(
        color: baseBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentBorder, width: 2.0),
        boxShadow: [
          BoxShadow(
            color: (statusUpper == 'CRITICAL')
                ? const Color(0xFFC62828).withValues(alpha: 0.6)
                : Colors.black.withValues(alpha: 0.3),
            blurRadius: (statusUpper == 'CRITICAL') ? 20 : 10,
            spreadRadius: (statusUpper == 'CRITICAL') ? 3 : 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(statusIcon, color: Colors.white, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI RISK STATUS',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                        color: Colors.white70,
                      ),
                    ),
                    Text(
                      widget.status.toUpperCase(),
                      style: GoogleFonts.outfit(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.0,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24, width: 1),
                ),
                child: Column(
                  children: [
                    Text(
                      'RISK SCORE',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white70,
                      ),
                    ),
                    Text(
                      '${widget.score.toStringAsFixed(1)}%',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  statusSubtitle,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (widget.lastUpdated.isNotEmpty)
                Text(
                  widget.lastUpdated.length > 19
                      ? widget.lastUpdated.substring(11, 19)
                      : widget.lastUpdated,
                  style: const TextStyle(fontSize: 11, color: Colors.white60),
                ),
            ],
          ),
        ],
      ),
    );

    if (statusUpper == 'CRITICAL') {
      return AnimatedBuilder(
        animation: _glowAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: 0.98 + (0.03 * _glowAnimation.value),
            child: Opacity(
              opacity: _glowAnimation.value,
              child: child,
            ),
          );
        },
        child: content,
      );
    }

    return content;
  }
}

/// Soil Moisture Telemetry Gauge Card
class MoistureGaugeCard extends StatelessWidget {
  final double moisture;

  const MoistureGaugeCard({super.key, required this.moisture});

  @override
  Widget build(BuildContext context) {
    // Dynamic color depending on saturation percentage
    Color gaugeColor;
    String statusNote;
    if (moisture >= 75.0) {
      gaugeColor = const Color(0xFFEF4444); // Hazardous saturation
      statusNote = 'Critically Saturated';
    } else if (moisture >= 45.0) {
      gaugeColor = const Color(0xFFF59E0B); // Moderately damp
      statusNote = 'Moist Soil Mantle';
    } else {
      gaugeColor = const Color(0xFF38BDF8); // Dry / stable
      statusNote = 'Dry / Well Drained';
    }

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.water_drop_rounded, size: 20, color: Color(0xFF38BDF8)),
                const SizedBox(width: 8),
                Text(
                  'Soil Saturation',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  height: 110,
                  width: 110,
                  child: CircularProgressIndicator(
                    value: (moisture / 100.0).clamp(0.0, 1.0),
                    strokeWidth: 11,
                    strokeCap: StrokeCap.round,
                    backgroundColor: const Color(0xFF243044),
                    color: gaugeColor,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${moisture.toStringAsFixed(1)}%',
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Moisture',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: gaugeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                statusNote,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: gaugeColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// IMU MPU6050 3-Axis Acceleration & Vibration Gauge Card
class AccelerationGaugeCard extends StatelessWidget {
  final double accelX;
  final double accelY;
  final double accelZ;

  const AccelerationGaugeCard({
    super.key,
    required this.accelX,
    required this.accelY,
    required this.accelZ,
  });

  @override
  Widget build(BuildContext context) {
    // Total vector magnitude |a| = sqrt(x^2 + y^2 + z^2)
    final double magnitude = sqrt(accelX * accelX + accelY * accelY + accelZ * accelZ);
    // Baseline gravity is 9.8 m/s^2. Deviation represents dynamic kinetic vibration
    final double vibration = (magnitude > 4.0) ? (magnitude - 9.806).abs() : (magnitude - 1.0).abs() * 9.806;

    Color vibColor = const Color(0xFF34D399);
    if (vibration >= 2.5) {
      vibColor = const Color(0xFFEF4444);
    } else if (vibration >= 1.0) {
      vibColor = const Color(0xFFF59E0B);
    }

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.vibration_rounded, size: 20, color: Color(0xFFF472B6)),
                const SizedBox(width: 8),
                Text(
                  'IMU Motion',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildAxisRow('X', accelX, const Color(0xFFF87171)),
            const SizedBox(height: 8),
            _buildAxisRow('Y', accelY, const Color(0xFF34D399)),
            const SizedBox(height: 8),
            _buildAxisRow('Z', accelZ, const Color(0xFF60A5FA)),
            const SizedBox(height: 14),
            const Divider(color: Color(0xFF2D3748), height: 1),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total |a|', style: TextStyle(fontSize: 11, color: Colors.white54)),
                    Text(
                      '${magnitude.toStringAsFixed(2)} m/s²',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: vibColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: vibColor.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    'Vib: ${vibration.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: vibColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAxisRow(String axis, double val, Color color) {
    // Standard normal range in m/s^2 is -16 to +16
    final double normalized = (val.abs() / 16.0).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 18,
          child: Text(
            axis,
            style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: normalized,
              backgroundColor: const Color(0xFF243044),
              color: color,
              minHeight: 10,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 44,
          child: Text(
            val.toStringAsFixed(2),
            textAlign: TextAlign.right,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
        ),
      ],
    );
  }
}

/// GIS & Topographic Simulation Override Panel
class GISControlPanel extends StatefulWidget {
  const GISControlPanel({super.key});

  @override
  State<GISControlPanel> createState() => _GISControlPanelState();
}

class _GISControlPanelState extends State<GISControlPanel> {
  final _latCtrl = TextEditingController(text: '31.1048'); // Shimla / Himalayas baseline
  final _lngCtrl = TextEditingController(text: '77.1734');
  final _slopeCtrl = TextEditingController(text: '38.0');
  final _rainCtrl = TextEditingController(text: '110.0');

  @override
  void dispose() {
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _slopeCtrl.dispose();
    _rainCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.public_rounded, color: Color(0xFF38BDF8), size: 22),
                const SizedBox(width: 10),
                Text(
                  'GIS & Meteorological Configuration',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Simulate spatial coordinates, NASA SRTM hillslope angle, and IMD/GPM rainfall to test context-aware AI thresholding.',
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildTextField('Latitude (°N)', _latCtrl)),
                const SizedBox(width: 14),
                Expanded(child: _buildTextField('Longitude (°E)', _lngCtrl)),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _buildTextField('Slope Angle (°)', _slopeCtrl)),
                const SizedBox(width: 14),
                Expanded(child: _buildTextField('24h Rainfall (mm)', _rainCtrl)),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () {
                  final overrides = {
                    'lat': double.tryParse(_latCtrl.text) ?? 31.1048,
                    'lng': double.tryParse(_lngCtrl.text) ?? 77.1734,
                    'slope': double.tryParse(_slopeCtrl.text) ?? 38.0,
                    'rainfall': double.tryParse(_rainCtrl.text) ?? 110.0,
                  };
                  context.read<MqttService>().publishOverride(overrides);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: const [
                          Icon(Icons.check_circle, color: Colors.greenAccent),
                          SizedBox(width: 10),
                          Text('GIS & Rainfall Overrides published to AI Engine!'),
                        ],
                      ),
                      backgroundColor: const Color(0xFF161E2E),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                },
                icon: const Icon(Icons.sync_rounded),
                label: Text(
                  'SYNC GEOGRAPHY TO AI BACKEND',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
      style: GoogleFonts.jetBrainsMono(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13, color: Colors.white60),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.5),
        ),
        filled: true,
        fillColor: const Color(0xFF131A26),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}
