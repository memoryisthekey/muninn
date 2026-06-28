import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'widgets/bag_browser_card.dart';
import 'widgets/storage_card.dart';
import 'widgets/battery_indicator.dart';

const bool devMode = false;
// const String backendUrl = 'http://192.168.131.88:8000';
// const String backendUrl = 'http://192.168.76.88:8000';
const String backendUrl = 'http://127.0.0.1:8000';
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
      theme: ThemeData.dark(useMaterial3: true),
      home: const DashboardPage(),
    );
  }
}

class UiScale {
  UiScale(BuildContext context) {
    final size = MediaQuery.of(context).size;
    compact = size.height < 950 || size.width < 1500;

    pagePadding = compact ? 8 : 16;
    cardPadding = compact ? 10 : 18;
    gap = compact ? 8 : 14;
    title = compact ? 16 : 22;
    subtitle = compact ? 12 : 15;
    status = compact ? 13 : 17;
    icon = compact ? 13 : 17;
    buttonHeight = compact ? 30 : 38;
    tabHeight = compact ? 30 : 34;
  }

  late final bool compact;
  late final double pagePadding;
  late final double cardPadding;
  late final double gap;
  late final double title;
  late final double subtitle;
  late final double status;
  late final double icon;
  late final double buttonHeight;
  late final double tabHeight;
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Map<String, dynamic>? status;
  Timer? timer;

  bool get isLegion {
    return Platform.localHostname.toLowerCase().contains('legion');
  }

  Future<void> runLegionJoystickCommand(String action) async {
    final allowed = ['start', 'stop', 'restart'];

    if (!allowed.contains(action)) {
      debugPrint('Invalid joystick service action: $action');
      return;
    }

    try {
      final result = await Process.run(
        'sudo',
        ['systemctl', action, 'legion_joystick_node.service'],
      );

      if (result.exitCode != 0) {
        debugPrint('Joystick service command failed: ${result.stderr}');
      } else {
        debugPrint('Joystick service command succeeded: $action');
      }
    } catch (e) {
      debugPrint('Joystick service command error: $e');
    }

    await fetchStatus();
  }

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
        mockStatus['camera_rtk_running_count'] = mockStatus['camera_rtk_total_count'];

        final sensors = mockStatus['sensors'] as Map<String, dynamic>;
        for (final sensor in sensors.values) {
          sensor['running'] = true;
          sensor['launched_by_backend'] = true;
        }
      }

      if (path == '/sensors/stop') {
        mockStatus['all_sensors_launch_running'] = false;
        mockStatus['camera_rtk_running_count'] = 0;
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
    final ui = UiScale(context);
    final tabCount = isLegion ? 4 : 3;

    return DefaultTabController(
      length: tabCount,
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(ui.tabHeight),
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: ui.tabHeight,
                child: TabBar(
                  labelPadding: const EdgeInsets.symmetric(horizontal: 10),
                  indicatorSize: TabBarIndicatorSize.label,
                  tabs: [
                    Tab(
                      height: ui.tabHeight,
                      child: Text(
                        'Dashboard',
                        style: TextStyle(fontSize: ui.compact ? 13 : 15),
                      ),
                    ),
                    Tab(
                      height: ui.tabHeight,
                      child: Text(
                        'Data',
                        style: TextStyle(fontSize: ui.compact ? 13 : 15),
                      ),
                    ),
                    Tab(
                      height: ui.tabHeight,
                      child: BatteryTabLabel(
                        battery: status?['battery'] as Map<String, dynamic>?,
                        fontSize: ui.compact ? 13 : 15,
                      ),
                    ),
                    if (isLegion)
                      Tab(
                        height: ui.tabHeight,
                        child: Text(
                          'Legion',
                          style: TextStyle(fontSize: ui.compact ? 13 : 15),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: status == null
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  DashboardView(
                    status: status!,
                    onPost: post,
                  ),
                  const DataManagementView(),
                  DiagnosticsView(status: status!),
                  if (isLegion)
                    LegionControlsView(
                      onStart: () => runLegionJoystickCommand('start'),
                      onStop: () => runLegionJoystickCommand('stop'),
                      onRestart: () => runLegionJoystickCommand('restart'),
                    ),
                ],
              ),
      ),
    );
  }
}

class BatteryTabLabel extends StatelessWidget {
  const BatteryTabLabel({
    super.key,
    required this.battery,
    required this.fontSize,
  });

  final Map<String, dynamic>? battery;
  final double fontSize;

  IconData get icon {
    final percentage = battery?['percentage'];

    if (percentage is! num) {
      return Icons.battery_unknown;
    }

    final value = percentage.clamp(0, 100).toInt();

    if (value >= 90) return Icons.battery_full;
    if (value >= 60) return Icons.battery_5_bar;
    if (value >= 40) return Icons.battery_4_bar;
    if (value >= 20) return Icons.battery_2_bar;
    return Icons.battery_alert;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: fontSize + 5),
        const SizedBox(width: 5),
        Text(
          battery?['percentage'] is num
              ? '${(battery!['percentage'] as num).toInt()}%  Diagnostics'
              : '--%  Diagnostics',
          style: TextStyle(fontSize: fontSize),
        ),
      ],
    );
  }
}

class DiagnosticsView extends StatelessWidget {
  const DiagnosticsView({
    super.key,
    required this.status,
  });

  final Map<String, dynamic> status;

  @override
  Widget build(BuildContext context) {
    final ui = UiScale(context);
    final battery = status['battery'] as Map<String, dynamic>?;

    return ListView(
      padding: EdgeInsets.all(ui.pagePadding),
      children: [
        Text(
          'Diagnostics',
          style: TextStyle(fontSize: ui.title, fontWeight: FontWeight.w600),
        ),
        SizedBox(height: ui.gap),
        BatteryStatusCard(battery: battery),
      ],
    );
  }
}

class BatteryStatusCard extends StatelessWidget {
  const BatteryStatusCard({
    super.key,
    required this.battery,
  });

  final Map<String, dynamic>? battery;

  @override
  Widget build(BuildContext context) {
    final ui = UiScale(context);
    final percentage = battery?['percentage'];
    final available = percentage is num;
    final value = available ? percentage.clamp(0, 100).toInt() : null;

    return Card(
      elevation: 5,
      child: Padding(
        padding: EdgeInsets.all(ui.cardPadding),
        child: Row(
          children: [
            BatteryIndicator(battery: battery),
            SizedBox(width: ui.gap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Robot Battery',
                    style: TextStyle(
                      fontSize: ui.title,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    available ? '$value%' : 'Unavailable',
                    style: TextStyle(
                      fontSize: ui.status,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DashboardView extends StatelessWidget {
  const DashboardView({
    super.key,
    required this.status,
    required this.onPost,
  });

  final Map<String, dynamic> status;
  final Future<void> Function(String path) onPost;

  @override
  Widget build(BuildContext context) {
    final ui = UiScale(context);
    final recording = status['recording'] == true;

    final sensorsMap = status['sensors'] as Map<String, dynamic>? ?? {};
    final statusOnlyMap = status['status_only'] as Map<String, dynamic>? ?? {};

    final launchableSensors = sensorsMap.entries.toList();
    final statusOnlyNodes = statusOnlyMap.entries.toList();

    final runningSensors = status['camera_rtk_running_count'] ?? 0;
    final totalSensors = status['camera_rtk_total_count'] ?? launchableSensors.length;

    final allItems = [
      ...launchableSensors,
      ...statusOnlyNodes,
    ];

    final currentBagName = status['current_bag_name'] as String?;
    final currentBagPath = status['current_bag_path'] as String?;
    final lastCompletedBagName = status['last_completed_bag_name'] as String?;

    return ListView(
      padding: EdgeInsets.all(ui.pagePadding),
      children: [
        RecordingCard(
          isRecording: recording,
          currentBagName: currentBagName,
          currentBagPath: currentBagPath,
          lastCompletedBagName: lastCompletedBagName,
          onStart: () => onPost('/recording/start'),
          onStop: () => onPost('/recording/stop'),
        ),
        SizedBox(height: ui.gap),
        Text(
          'System Status',
          style: TextStyle(fontSize: ui.title, fontWeight: FontWeight.w600),
        ),
        SizedBox(height: ui.gap),
        ResponsiveSystemGrid(
          runningSensors: runningSensors,
          totalSensors: totalSensors,
          onStartAll: () => onPost('/sensors/start'),
          onStopAll: () => onPost('/sensors/stop'),
          items: allItems,
          onStart: (key) => onPost('/sensor/$key/start'),
          onStop: (key) => onPost('/sensor/$key/stop'),
        ),
      ],
    );
  }
}


class DataManagementView extends StatelessWidget {
  const DataManagementView({super.key});

  @override
  Widget build(BuildContext context) {
    final ui = UiScale(context);

    return ListView(
      padding: EdgeInsets.all(ui.pagePadding),
      children: [
        StorageCard(
  backendUrl: backendUrl,
),

        SizedBox(height: ui.gap),
        const BagBrowserCard(
  backendUrl: backendUrl,
),
      ],
    );
  }
}

class LegionControlsView extends StatelessWidget {
  const LegionControlsView({
    super.key,
    required this.onStart,
    required this.onStop,
    required this.onRestart,
  });

  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final ui = UiScale(context);

    return ListView(
      padding: EdgeInsets.all(ui.pagePadding),
      children: [
        LegionJoystickCard(
          onStart: onStart,
          onStop: onStop,
          onRestart: onRestart,
        ),
      ],
    );
  }
}

class RecordingCard extends StatelessWidget {
  const RecordingCard({
    super.key,
    required this.isRecording,
    required this.onStart,
    required this.onStop,
    this.currentBagName,
    this.currentBagPath,
    this.lastCompletedBagName,
  });

  final bool isRecording;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final String? currentBagName;
  final String? currentBagPath;
  final String? lastCompletedBagName;

  @override
  Widget build(BuildContext context) {
    final ui = UiScale(context);
    final statusColor = isRecording ? Colors.redAccent : Colors.greenAccent;

    final bagName = isRecording
        ? currentBagName
        : lastCompletedBagName ?? currentBagName;

    final bagLabel = isRecording ? 'Current bag' : 'Last bag';

    return Card(
      elevation: 5,
      child: Padding(
        padding: EdgeInsets.all(ui.cardPadding),
        child: Row(
          children: [
            Icon(Icons.fiber_manual_record, color: statusColor, size: ui.icon),
            SizedBox(width: ui.gap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Recording',
                    style: TextStyle(
                      fontSize: ui.title,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isRecording ? 'Recording active' : 'Ready to record',
                    style: TextStyle(
                      color: statusColor,
                      fontSize: ui.status,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (bagName != null && bagName.isNotEmpty) ...[
                    SizedBox(height: ui.gap / 2),
                    Text(
                      bagLabel,
                      style: TextStyle(
                        fontSize: ui.subtitle - 1,
                        color: Colors.grey,
                      ),
                    ),
                    Text(
                      bagName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: ui.subtitle,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (isRecording &&
                      currentBagPath != null &&
                      currentBagPath!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      currentBagPath!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: ui.subtitle - 2,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            CompactButton(
              onPressed: isRecording ? null : onStart,
              icon: Icons.play_arrow,
              label: 'Start',
            ),
            SizedBox(width: ui.gap),
            CompactButton(
              onPressed: isRecording ? onStop : null,
              icon: Icons.stop,
              label: 'Stop',
            ),
          ],
        ),
      ),
    );
  }
}

class CameraRtkGridCard extends StatelessWidget {
  const CameraRtkGridCard({
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
    final ui = UiScale(context);
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
      elevation: 5,
      child: Padding(
        padding: EdgeInsets.all(ui.cardPadding),
        child: Row(
          children: [
            Icon(Icons.circle, color: statusColor, size: ui.icon),
            SizedBox(width: ui.gap),
            Expanded(
              child: Column(
  mainAxisAlignment: MainAxisAlignment.center,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(
      'Camera + RTK',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: ui.subtitle + 1,
        fontWeight: FontWeight.bold,
      ),
    ),

    const SizedBox(height: 4),

    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline,
          size: ui.icon,
          color: Colors.grey,
        ),
        const SizedBox(width: 6),
        const Expanded(
          child: Text(
            'Starts the RealSense camera, Ublox GPS and NTRIP client.',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey,
            ),
          ),
        ),
      ],
    ),

    const SizedBox(height: 6),

    Text(
      statusText,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: statusColor,
        fontSize: ui.subtitle,
        fontWeight: FontWeight.w600,
      ),
    ),
  ],
),
            ),
            SizedBox(width: ui.gap),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CompactButton(
                  onPressed: allRunning ? null : onStartAll,
                  icon: Icons.play_arrow,
                  label: 'Launch',
                ),
                const SizedBox(height: 6),
                CompactButton(
                  onPressed: noneRunning ? null : onStopAll,
                  icon: Icons.stop,
                  label: 'Stop',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class LegionJoystickCard extends StatelessWidget {
  const LegionJoystickCard({
    super.key,
    required this.onStart,
    required this.onStop,
    required this.onRestart,
  });

  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final ui = UiScale(context);

    return Card(
      elevation: 5,
      child: Padding(
        padding: EdgeInsets.all(ui.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Legion Joystick Service',
              style: TextStyle(fontSize: ui.title, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: ui.gap),
            Row(
              children: [
                Expanded(
                  child: CompactButton(
                    onPressed: onStart,
                    icon: Icons.play_arrow,
                    label: 'Start',
                  ),
                ),
                SizedBox(width: ui.gap),
                Expanded(
                  child: CompactButton(
                    onPressed: onStop,
                    icon: Icons.stop,
                    label: 'Stop',
                  ),
                ),
                SizedBox(width: ui.gap),
                Expanded(
                  child: CompactButton(
                    onPressed: onRestart,
                    icon: Icons.restart_alt,
                    label: 'Restart',
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

class ResponsiveSystemGrid extends StatelessWidget {
  const ResponsiveSystemGrid({
    super.key,
    required this.runningSensors,
    required this.totalSensors,
    required this.onStartAll,
    required this.onStopAll,
    required this.items,
    required this.onStart,
    required this.onStop,
  });

  final int runningSensors;
  final int totalSensors;
  final VoidCallback onStartAll;
  final VoidCallback onStopAll;
  final List<MapEntry<String, dynamic>> items;
  final void Function(String key) onStart;
  final void Function(String key) onStop;

  @override
  Widget build(BuildContext context) {
    final ui = UiScale(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        final crossAxisCount = width > 1300
            ? 3
            : width > 720
                ? 2
                : 1;

        final aspectRatio = width > 1300
            ? 3.2
            : width > 720
                ? 2.9
                : 3.6;

        final cards = <Widget>[
          CameraRtkGridCard(
            runningSensors: runningSensors,
            totalSensors: totalSensors,
            onStartAll: onStartAll,
            onStopAll: onStopAll,
          ),
          ...items.map((entry) {
            final key = entry.key;
            final sensor = entry.value as Map<String, dynamic>;

            final launchable = sensor['launchable'] == true;
            final running = sensor['running'] == true;
            final launchedByBackend = sensor['launched_by_backend'] == true;

            return SensorCard(
              sensorKey: key,
              displayName: sensor['display_name'] ?? key,
              rosNodeName: sensor['ros_node_name'] ?? '',
              running: running,
              launchedByBackend: launchedByBackend,
              launchable: launchable,
              onStart: () => onStart(key),
              onStop: () => onStop(key),
            );
          }),
        ];

        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: ui.gap,
          mainAxisSpacing: ui.gap,
          childAspectRatio: aspectRatio,
          children: cards,
        );
      },
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
    final ui = UiScale(context);
    final statusColor = running ? Colors.greenAccent : Colors.redAccent;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(ui.cardPadding),
        child: Row(
          children: [
            Icon(Icons.circle, color: statusColor, size: ui.icon),
            SizedBox(width: ui.gap),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: ui.subtitle + 1,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    rosNodeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: ui.subtitle),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    launchedByBackend ? 'Launched by backend' : 'Detected from ROS',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: ui.subtitle - 1),
                  ),
                ],
              ),
            ),
            if (launchable) ...[
              SizedBox(width: ui.gap),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CompactButton(
                    onPressed: running ? null : onStart,
                    icon: Icons.play_arrow,
                    label: 'Start',
                  ),
                  const SizedBox(height: 6),
                  CompactButton(
                    onPressed: running ? onStop : null,
                    icon: Icons.stop,
                    label: 'Stop',
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class CompactButton extends StatelessWidget {
  const CompactButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ui = UiScale(context);

    return SizedBox(
      height: ui.buttonHeight,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: ui.icon),
        label: Text(
          label,
          style: TextStyle(fontSize: ui.subtitle),
        ),
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.symmetric(horizontal: ui.compact ? 8 : 14),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

final Map<String, dynamic> mockStatus = {
  "ok": true,
  "recording": false,
  "current_bag_name": null,
  "current_bag_path": null,
  "last_completed_bag_name": "husky_sensor_bag_20260626_230211",
  "all_sensors_launch_running": false,
  "camera_rtk_running_count": 0,
  "camera_rtk_total_count": 3,
  "sensors": {
    "realsense": {
      "display_name": "RealSense D435",
      "ros_node_name": "/camera/camera",
      "running": false,
      "launched_by_backend": false,
      "launchable": true,
    },
    "ublox": {
      "display_name": "Ublox GPS",
      "ros_node_name": "/ublox_gps_node",
      "running": false,
      "launched_by_backend": false,
      "launchable": true,
    },
    "ntrip": {
      "display_name": "NTRIP Client",
      "ros_node_name": "/ntrip_client",
      "running": false,
      "launched_by_backend": false,
      "launchable": true,
    },
  },
  "battery": {
    "percentage": 84,
  },
  "status_only": {
    "imu": {
      "display_name": "IMU",
      "ros_node_name": "/a300_00008/sensors/imu_0/phidgets_spatial",
      "running": false,
    },
    "lidar": {
      "display_name": "Ouster 3D Lidar",
      "ros_node_name": "/a300_00008/sensors/lidar3d_0/ouster_driver",
      "running": false,
    },
  },
};