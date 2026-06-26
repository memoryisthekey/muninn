import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const bool devMode = true;
//const String backendUrl = 'http://192.168.131.88:8000';
const String backendUrl = 'http://192.168.76.88:8000';
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

    try {
      final response = await http.get(Uri.parse('$backendUrl/status'));

      if (response.statusCode == 200) {
        setState(() {
          status = jsonDecode(response.body);
        });
      }
    } catch (e) {
      debugPrint('Status fetch failed: $e');
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

        final sensors = mockStatus['sensors'] as Map<String, dynamic>;
        for (final sensor in sensors.values) {
          sensor['running'] = true;
          sensor['launched_by_backend'] = true;
        }
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

    final sensorsMap = status?['sensors'] as Map<String, dynamic>? ?? {};
    final statusOnlyMap = status?['status_only'] as Map<String, dynamic>? ?? {};

    final launchableSensors = sensorsMap.entries.toList();
    final statusOnlyNodes = statusOnlyMap.entries.toList();

    final runningSensors = status?['camera_rtk_running_count'] ?? 0;
    final totalSensors = status?['camera_rtk_total_count'] ?? launchableSensors.length;

    final allItems = [
      ...launchableSensors,
      ...statusOnlyNodes,
    ];

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
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
                    runningSensors: runningSensors,
                    totalSensors: totalSensors,
                    onStartAll: () => post('/sensors/start'),
                    onStopAll: () => post('/sensors/stop'),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'System Status',
                    style: TextStyle(fontSize: 22),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.builder(
                      itemCount: allItems.length,
                      itemBuilder: (context, index) {
                        final entry = allItems[index];
                        final key = entry.key;
                        final sensor = entry.value as Map<String, dynamic>;
                        final launchable = sensor['launchable'] == true;

                        final running = sensor['running'] == true;
                        final launchedByBackend =
                            sensor['launched_by_backend'] == true;

                        return SensorCard(
                          sensorKey: key,
                          displayName: sensor['display_name'] ?? key,
                          rosNodeName: sensor['ros_node_name'] ?? '',
                          running: running,
                          launchedByBackend: launchedByBackend,
                          launchable: launchable,
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
            const Text(
              'Recording',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
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
    required this.runningSensors,
    required this.totalSensors,
    required this.onStartAll,
    required this.onStopAll,
  });

  final int runningSensors;
  final int totalSensors;
  final VoidCallback onStartAll;
  final VoidCallback onStopAll;

  @override
  Widget build(BuildContext context) {
    final allRunning = totalSensors > 0 && runningSensors == totalSensors;
    final noneRunning = runningSensors == 0;

    final Color statusColor = allRunning
        ? Colors.greenAccent
        : noneRunning
            ? Colors.redAccent
            : Colors.orangeAccent;

    final String statusText = allRunning
        ? 'All systems running'
        : noneRunning
            ? 'No systems running'
            : '$runningSensors / $totalSensors systems running';

    return Card(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Camera and RTK Launch',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.circle, color: statusColor, size: 18),
                const SizedBox(width: 8),
                Text(
                  statusText,
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
                    onPressed: allRunning ? null : onStartAll,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Launch'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: noneRunning ? null : onStopAll,
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
    required this.launchable,
  });

  final String sensorKey;
  final String displayName;
  final String rosNodeName;
  final bool running;
  final bool launchedByBackend;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final bool launchable;

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
        trailing: launchable
        ? Wrap(
            spacing: 8,
            children: [
              ElevatedButton(
                onPressed: running ? null : onStart,
                child: const Text('Launch'),
              ),
              ElevatedButton(
                onPressed: running ? onStop : null,
                child: const Text('Stop'),
              ),
            ],
          )
        : null,
  ) ,
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
    "imu": {
      "display_name": "IMU",
      "ros_node_name": "/a300_00008/sensors/imu_0",
      "running": true,
      "launched_by_backend": false,
    },
    "ouster_driver": {
      "display_name": "Ouster Driver",
      "ros_node_name": "/a300_00008/ouster_driver",
      "running": true,
      "launched_by_backend": false,
    },
  },
};