
import 'package:flutter/material.dart';

class BatteryIndicator extends StatelessWidget {
  final Map<String, dynamic>? battery;

  const BatteryIndicator({
    super.key,
    required this.battery,
  });

  @override
  Widget build(BuildContext context) {
    final percentage = battery?['percentage'];

    final available = percentage is num;
    final value = available ? percentage.clamp(0, 100).toInt() : null;

    IconData icon;

    if (!available) {
      icon = Icons.battery_unknown;
    } else if (value! >= 90) {
      icon = Icons.battery_full;
    } else if (value >= 60) {
      icon = Icons.battery_5_bar;
    } else if (value >= 40) {
      icon = Icons.battery_4_bar;
    } else if (value >= 20) {
      icon = Icons.battery_2_bar;
    } else {
      icon = Icons.battery_alert;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 24),
        const SizedBox(width: 4),
        Text(
          available ? '$value%' : '--%',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}