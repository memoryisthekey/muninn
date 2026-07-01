import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class StorageCard extends StatefulWidget {
  final String backendUrl;

  const StorageCard({
    super.key,
    required this.backendUrl,
  });

  @override
  State<StorageCard> createState() => _StorageCardState();
}

class _StorageCardState extends State<StorageCard> {
  Timer? _timer;

  Map<String, dynamic>? bags;
  Map<String, dynamic>? usbStorage;
  Map<String, dynamic>? usbStatus;

  @override
  void initState() {
    super.initState();

    fetchStorage();

    _timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => fetchStorage(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> fetchStorage() async {
    try {
      final response =
          await http.get(Uri.parse('${widget.backendUrl}/status'));

      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body);

      final storage = data['storage'];

      if (!mounted) return;

      setState(() {
        bags = storage['bags'];
        usbStorage = storage['usb'];
        usbStatus = data['usb'] as Map<String, dynamic>?;
      });
    } catch (_) {}
  }

  Widget buildStorageSection({
    required String title,
    required Map<String, dynamic>? storage,
    required IconData icon,
  }) {
    if (storage == null || storage['available'] != true) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon),
              const SizedBox(width: 8),
              Text(
                title,
                style:
                    const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text("Not available"),
        ],
      );
    }

    final used = (storage['used_gb'] as num).toDouble();
    final total = (storage['total_gb'] as num).toDouble();
    final percent =
        (storage['used_percent'] as num).toDouble() / 100.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon),
            const SizedBox(width: 8),
            Text(
              title,
              style:
                  const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LinearProgressIndicator(value: percent),
        const SizedBox(height: 8),
        Text(
          '${used.toStringAsFixed(1)} GB / ${total.toStringAsFixed(1)} GB used',
        ),
        Text(
          '${storage["free_gb"]} GB free',
          style: const TextStyle(
            color: Colors.grey,
          ),
        ),
      ],
    );
  }


  Future<void> mountUsb() async {
    try {
      await http.post(Uri.parse('${widget.backendUrl}/usb/mount'));
      await fetchStorage();
    } catch (e) {
      debugPrint('USB mount failed: $e');
    }
  }

  Future<void> ejectUsb() async {
    try {
      await http.post(Uri.parse('${widget.backendUrl}/usb/eject'));
      await fetchStorage();
    } catch (e) {
      debugPrint('USB eject failed: $e');
    }
  }

  Widget buildUsbStorageSection() {
    final connected = usbStatus?['connected'] == true;
    final mounted = usbStatus?['mounted'] == true;
    final writable = usbStatus?['writable'] == true;

    final statusText = !connected
        ? 'No USB drive detected'
        : !mounted
            ? 'USB detected, not mounted'
            : !writable
                ? 'USB mounted, not writable'
                : 'USB ready';

    final statusColor = !connected
        ? Colors.grey
        : !mounted
            ? Colors.orangeAccent
            : !writable
                ? Colors.redAccent
                : Colors.greenAccent;

    final statusIcon = !connected
        ? Icons.usb_off
        : !mounted
            ? Icons.usb
            : !writable
                ? Icons.warning_amber_rounded
                : Icons.check_circle_outline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.usb),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'USB Storage',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Icon(statusIcon, size: 18, color: statusColor),
            const SizedBox(width: 6),
            Text(
              statusText,
              style: TextStyle(color: statusColor),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (!mounted)
          const Text(
            'Not mounted',
            style: TextStyle(color: Colors.grey),
          )
        else
          buildStorageSection(
            title: 'USB Usage',
            storage: usbStorage,
            icon: Icons.drive_folder_upload,
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (connected && !mounted)
              FilledButton.icon(
                onPressed: mountUsb,
                icon: const Icon(Icons.usb),
                label: const Text('Mount Disk'),
              ),
            if (mounted)
              OutlinedButton.icon(
                onPressed: ejectUsb,
                icon: const Icon(Icons.eject),
                label: const Text('Safely Remove'),
              ),
          ],
        ),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Text(
              'Storage',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 20),

            buildStorageSection(
              title: 'NUC Storage',
              storage: bags,
              icon: Icons.storage,
            ),

            const SizedBox(height: 24),

            buildUsbStorageSection(),
          ],
        ),
      ),
    );
  }
}