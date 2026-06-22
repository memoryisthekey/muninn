import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

//Change this if not MOCK
const bool devMode = true;
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
        status = mockStatus;
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

      if (path == '/record/start') {
        setState(() {
          mockStatus['recording'] = true;
          status = Map<String, dynamic>.from(mockStatus);
        });
      }

      if (path == '/record/stop') {
        setState(() {
          mockStatus['recording'] = false;
          status = Map<String, dynamic>.from(mockStatus);
        });
      }

      return;
    }

    await http.post(Uri.parse('$backendUrl$path'));
    await fetchStatus();
  }

  @override
  Widget build(BuildContext context) {
    final nodes = status?['required_nodes'] as List<dynamic>? ?? [];
    final recording = status?['recording'] == true;

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
                    onStart: () => post('/record/start'),
                    onStop: () => post('/record/stop'),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Required Nodes',
                    style: TextStyle(fontSize: 22),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.builder(
                      itemCount: nodes.length,
                      itemBuilder: (context, index) {
                        final node = nodes[index];
                        final running = node['running'] == true;

                        return Card(
                          child: ListTile(
                            leading: Icon(
                              Icons.circle,
                              color: running
                                  ? Colors.greenAccent
                                  : Colors.redAccent,
                            ),
                            title: Text(node['display_name'] ?? node['key']),
                            subtitle: Text(node['ros_node_name'] ?? ''),
                            trailing: Wrap(
                              spacing: 8,
                              children: [
                                ElevatedButton(
                                  onPressed: () =>
                                      post('/launch/${node['key']}'),
                                  child: const Text('Launch'),
                                ),
                                ElevatedButton(
                                  onPressed: () =>
                                      post('/stop/${node['key']}'),
                                  child: const Text('Stop'),
                                ),
                              ],
                            ),
                          ),
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
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              Colors.grey.shade900,
              Colors.grey.shade800,
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recording',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  Icons.fiber_manual_record,
                  color: statusColor,
                  size: 18,
                ),
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
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
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
}

final Map<String, dynamic> mockStatus = {
  "recording": false,
  "required_nodes": [
    {
      "key": "ouster",
      "display_name": "Ouster 3D Lidar",
      "ros_node_name": "/a300_00008/os_driver",
      "running": true,
    },
    {
      "key": "realsense",
      "display_name": "RealSense D435",
      "ros_node_name": "/a300_00008/camera/camera",
      "running": false,
    },
    {
      "key": "joystick",
      "display_name": "Legion Joystick",
      "ros_node_name": "/joy_node",
      "running": true,
    },
  ],
};