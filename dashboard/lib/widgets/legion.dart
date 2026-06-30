import 'package:flutter/material.dart';

class LegionControlsView extends StatelessWidget {
  const LegionControlsView({
    super.key,
    required this.running,
    required this.connected,
    required this.serviceStatus,
    required this.detail,
    required this.onStart,
    required this.onStop,
    required this.onRestart,
    required this.zenohRunning,
    required this.zenohStatus,
    required this.onRestartZenoh,
  });

  final bool running;
  final bool connected;
  final String serviceStatus;
  final String detail;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRestart;

  final bool zenohRunning;
  final String zenohStatus;
  final VoidCallback onRestartZenoh;

  @override
  Widget build(BuildContext context) {
    final spacing = _LegionScale.spacing(context);

    return ListView(
      padding: EdgeInsets.all(_LegionScale.pagePadding(context)),
      children: [
        LegionJoystickCard(
          running: running,
          connected: connected,
          serviceStatus: serviceStatus,
          detail: detail,
          onStart: onStart,
          onStop: onStop,
          onRestart: onRestart,
        ),
        SizedBox(height: spacing),
        ZenohBridgeCard(
          running: zenohRunning,
          serviceStatus: zenohStatus,
          onRestart: onRestartZenoh,
        ),
        SizedBox(height: spacing),
        const _LegionInfoCard(),
      ],
    );
  }
}

class LegionJoystickCard extends StatelessWidget {
  const LegionJoystickCard({
    super.key,
    required this.running,
    required this.connected,
    required this.serviceStatus,
    required this.detail,
    required this.onStart,
    required this.onStop,
    required this.onRestart,
  });

  final bool running;
  final bool connected;
  final String serviceStatus;
  final String detail;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final titleSize = _LegionScale.title(context);
    final statusSize = _LegionScale.status(context);
    final spacing = _LegionScale.spacing(context);
    final padding = _LegionScale.cardPadding(context);

    final ready = running && connected;
    final statusColor = ready
        ? Colors.greenAccent
        : running
            ? Colors.orangeAccent
            : Colors.redAccent;
    final statusText = ready
        ? 'Ready'
        : running
            ? 'Service active'
            : 'Stopped';

    return Card(
      elevation: 5,
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Legion Joystick',
              style: TextStyle(
                fontSize: titleSize,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: spacing),
            _StatusLine(
              color: statusColor,
              text: '$statusText ($serviceStatus)',
            ),
            SizedBox(height: spacing * 0.5),
            Text(
              detail,
              style: TextStyle(
                fontSize: statusSize * 0.9,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            SizedBox(height: spacing),
            Row(
              children: [
                Expanded(
                  child: _LegionButton(
                    onPressed: running ? null : onStart,
                    icon: Icons.play_arrow,
                    label: 'Start',
                  ),
                ),
                SizedBox(width: spacing),
                Expanded(
                  child: _LegionButton(
                    onPressed: running ? onStop : null,
                    icon: Icons.stop,
                    label: 'Stop',
                  ),
                ),
                SizedBox(width: spacing),
                Expanded(
                  child: _LegionButton(
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

class ZenohBridgeCard extends StatelessWidget {
  const ZenohBridgeCard({
    super.key,
    required this.running,
    required this.serviceStatus,
    required this.onRestart,
  });

  final bool running;
  final String serviceStatus;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final titleSize = _LegionScale.title(context);
    final spacing = _LegionScale.spacing(context);
    final padding = _LegionScale.cardPadding(context);

    return Card(
      elevation: 5,
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Zenoh Bridge',
              style: TextStyle(
                fontSize: titleSize,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: spacing),
            _StatusLine(
              color: running ? Colors.greenAccent : Colors.redAccent,
              text: running ? 'Running ($serviceStatus)' : 'Stopped ($serviceStatus)',
            ),
            SizedBox(height: spacing),
            SizedBox(
              width: double.infinity,
              child: _LegionButton(
                onPressed: onRestart,
                icon: Icons.restart_alt,
                label: 'Restart Zenoh',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.color,
    required this.text,
  });

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final iconSize = _LegionScale.icon(context);
    final statusSize = _LegionScale.status(context);

    return Row(
      children: [
        Icon(Icons.circle, size: iconSize, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: statusSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _LegionInfoCard extends StatelessWidget {
  const _LegionInfoCard();

  @override
  Widget build(BuildContext context) {
    final padding = _LegionScale.cardPadding(context);
    final statusSize = _LegionScale.status(context);

    return Card(
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Text(
          'Joystick status now separates the systemd service from the physical /dev/input/js* device. Ready means the service is active and a joystick is connected.',
          style: TextStyle(fontSize: statusSize * 0.9),
        ),
      ),
    );
  }
}

class _LegionButton extends StatelessWidget {
  const _LegionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final compact = _LegionScale.compact(context);

    return SizedBox(
      height: compact ? 30 : 38,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: compact ? 15 : 18),
        label: Text(
          label,
          style: TextStyle(fontSize: compact ? 12 : 14),
        ),
      ),
    );
  }
}

class _LegionScale {
  static bool compact(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.height < 950 || size.width < 1500;
  }

  static double pagePadding(BuildContext context) => compact(context) ? 8 : 16;

  static double cardPadding(BuildContext context) => compact(context) ? 10 : 18;

  static double spacing(BuildContext context) => compact(context) ? 8 : 14;

  static double title(BuildContext context) => compact(context) ? 16 : 22;

  static double status(BuildContext context) => compact(context) ? 13 : 17;

  static double icon(BuildContext context) => compact(context) ? 13 : 17;
}