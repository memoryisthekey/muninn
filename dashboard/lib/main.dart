import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const bool devMode = false;
const String backendUrl = 'http://localhost:8000';

void main() {
  runApp(const MuninnApp());
}

class MuninnApp extends StatelessWidget {
  const MuninnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Muninn',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Map<String, dynamic>? status;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    fetchStatus();
    timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => fetchStatus(),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> fetchStatus() async {
    if (devMode) {
      setState(() {
        status = Map<String, dynamic>.from(mockStatus);
      });
      return;
    }

    final response = await http.get(Uri.parse('$backendUrl/status'));

    if (response.statusCode == 200) {
      setState(() {
        status = jsonDecode(response.body);
      });
    }
  }

  Future<void> post(String path) async {
    if (devMode) {
      debugPrint('Mock POST: $path');

      if (path == '/recording/start') {
        mockStatus['recording'] = true;
      }

      if (path == '/recording/stop') {
        mockStatus['recording'] = false;
      }

      if (path == '/sensors/start') {
        mockStatus['all_sensors_launch_running'] = true;
      }

      if (path == '/sensors/stop') {
        mockStatus['all_sensors_launch_running'] = false;
      }

      setState(() {
        status = Map<String, dynamic>.from(mockStatus);
      });

      return;
    }

    await http.post(Uri.parse('$backendUrl$path'));
    await fetchStatus();
  }

  @override
  Widget build(BuildContext context) {
    final recording = status?['recording'] == true;
    final allSensorsRunning = status?['all_sensors_launch_running'] == true;

    final sensorsMap = status?['sensors'] as Map<String, dynamic>? ?? {};
    final sensors = sensorsMap.entries.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('🐦‍⬛ Muninn'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: status == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RecordingCard(
                    isRecording: recording,
                    onStart: () => post('/recording/start'),
                    onStop: () => post('/recording/stop'),
                  ),
                  const SizedBox(height: 16),
                  SensorsControlCard(
                    allSensorsRunning: allSensorsRunning,
                    onStartAll: () => post('/sensors/start'),
                    onStopAll: () => post('/sensors/stop'),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Sensors',
                    style: TextStyle(fontSize: 22),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.builder(
                      itemCount: sensors.length,
                      itemBuilder: (context, index) {
                        final entry = sensors[index];
                        final key = entry.key;
                        final sensor = entry.value as Map<String, dynamic>;

                        final running = sensor['running'] == true;
                        final launchedByBackend =
                            sensor['launched_by_backend'] == true;

                        return SensorCard(
                          sensorKey: key,
                          displayName: sensor['display_name'] ?? key,
                          rosNodeName: sensor['ros_node_name'] ?? '',
                          running: running,
                          launchedByBackend: launchedByBackend,
                          onStart: () => post('/sensor/$key/start'),
                          onStop: () => post('/sensor/$key/stop'),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class RecordingCard extends StatelessWidget {
  const RecordingCard({
    super.key,
    required this.isRecording,
    required this.onStart,
    required this.onStop,
  });

  final bool isRecording;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final statusColor = isRecording ? Colors.redAccent : Colors.greenAccent;

    return Card(
      elevation: 8,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Recording',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.fiber_manual_record, color: statusColor, size: 18),
                const SizedBox(width: 8),
                Text(
                  isRecording ? 'Recording active' : 'Ready to record',
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isRecording ? null : onStart,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isRecording ? onStop : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SensorsControlCard extends StatelessWidget {
  const SensorsControlCard({
    super.key,
    required this.allSensorsRunning,
    required this.onStartAll,
    required this.onStopAll,
  });

  final bool allSensorsRunning;
  final VoidCallback onStartAll;
  final VoidCallback onStopAll;

  @override
  Widget build(BuildContext context) {
    final statusColor =
        allSensorsRunning ? Colors.greenAccent : Colors.orangeAccent;

    return Card(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Sensor Launch',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.circle, color: statusColor, size: 18),
                const SizedBox(width: 8),
                Text(
                  allSensorsRunning
                      ? 'sensors.launch.py active'
                      : 'sensors.launch.py not active',
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: allSensorsRunning ? null : onStartAll,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Launch All'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: allSensorsRunning ? onStopAll : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop All'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SensorCard extends StatelessWidget {
  const SensorCard({
    super.key,
    required this.sensorKey,
    required this.displayName,
    required this.rosNodeName,
    required this.running,
    required this.launchedByBackend,
    required this.onStart,
    required this.onStop,
  });

  final String sensorKey;
  final String displayName;
  final String rosNodeName;
  final bool running;
  final bool launchedByBackend;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final statusColor = running ? Colors.greenAccent : Colors.redAccent;

    return Card(
      child: ListTile(
        leading: Icon(Icons.circle, color: statusColor),
        title: Text(displayName),
        subtitle: Text(
          '$rosNodeName\n${launchedByBackend ? "Launched by backend" : "Detected from ROS"}',
        ),
        isThreeLine: true,
        trailing: Wrap(
          spacing: 8,
          children: [
            ElevatedButton(
              onPressed: running ? null : onStart,
              child: const Text('Launch'),
            ),
            ElevatedButton(
              onPressed: launchedByBackend ? onStop : null,
              child: const Text('Stop'),
            ),
          ],
        ),
      ),
    );
  }
}

final Map<String, dynamic> mockStatus = {
  "ok": true,
  "recording": false,
  "all_sensors_launch_running": false,
  "sensors": {
    "ouster": {
      "display_name": "Ouster 3D Lidar",
      "ros_node_name": "/a300_00008/os_driver",
      "running": true,
      "launched_by_backend": false,
    },
    "realsense": {
      "display_name": "RealSense D435",
      "ros_node_name": "/camera/camera",
      "running": false,
      "launched_by_backend": false,
    },
    "ublox": {
      "display_name": "Ublox GPS",
      "ros_node_name": "/ublox_gps_node",
      "running": true,
      "launched_by_backend": false,
    },
    "ntrip": {
      "display_name": "NTRIP Client",
      "ros_node_name": "/ntrip_client",
      "running": true,
      "launched_by_backend": false,
    },
  },
};