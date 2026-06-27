import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class BagBrowserCard extends StatefulWidget {
  const BagBrowserCard({
    super.key,
    required this.backendUrl,
  });

  final String backendUrl;

  @override
  State<BagBrowserCard> createState() => _BagBrowserCardState();
}

class _BagBrowserCardState extends State<BagBrowserCard> {
  bool loading = true;
  String? error;
  String? bagsDirectory;
  List<BagInfo> bags = [];
  BagInfo? selectedBag;

  @override
  void initState() {
    super.initState();
    fetchBags();
  }

  Future<void> fetchBags() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final response = await http.get(
        Uri.parse('${widget.backendUrl}/bags'),
      );

      if (response.statusCode != 200) {
        throw Exception('Backend returned ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final loadedBags = (data['bags'] as List<dynamic>? ?? [])
          .map((item) => BagInfo.fromJson(item as Map<String, dynamic>))
          .toList();

      setState(() {
        bagsDirectory = data['bags_directory'] as String?;
        bags = loadedBags;

        if (selectedBag != null) {
          selectedBag = loadedBags
              .where((bag) => bag.name == selectedBag!.name)
              .cast<BagInfo?>()
              .firstWhere(
                (bag) => bag != null,
                orElse: () => null,
              );
        }

        loading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  void selectBag(BagInfo bag) {
    setState(() {
      selectedBag = bag;
    });
  }

  void clearSelectedBag() {
    setState(() {
      selectedBag = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ui = BagUiScale(context);

    return Card(
      elevation: 5,
      child: Padding(
        padding: EdgeInsets.all(ui.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectedBagPanel(
              ui: ui,
              bag: selectedBag,
              onClear: clearSelectedBag,
            ),
            SizedBox(height: ui.sectionGap),
            BagBrowserHeader(
              ui: ui,
              loading: loading,
              onRefresh: fetchBags,
            ),
            SizedBox(height: ui.gap),
            if (bagsDirectory != null && bagsDirectory!.isNotEmpty)
              Text(
                bagsDirectory!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: ui.caption,
                  color: Colors.grey,
                ),
              ),
            SizedBox(height: ui.gap),
            if (loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (error != null)
              BagErrorBox(
                ui: ui,
                message: error!,
                onRetry: fetchBags,
              )
            else if (bags.isEmpty)
              Text(
                'No bags found.',
                style: TextStyle(
                  fontSize: ui.body,
                  color: Colors.grey,
                ),
              )
            else
              BagList(
                ui: ui,
                bags: bags,
                selectedBag: selectedBag,
                onSelected: selectBag,
              ),
          ],
        ),
      ),
    );
  }
}

class BagInfo {
  const BagInfo({
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.modified,
    required this.latest,
    required this.recording,
    required this.transferAllowed,
  });

  final String name;
  final String path;
  final int sizeBytes;
  final String modified;
  final bool latest;
  final bool recording;
  final bool transferAllowed;

  factory BagInfo.fromJson(Map<String, dynamic> json) {
    return BagInfo(
      name: json['name']?.toString() ?? 'Unknown bag',
      path: json['path']?.toString() ?? '',
      sizeBytes: _readSizeBytes(json),
      modified: json['modified']?.toString() ?? '',
      latest: json['latest'] == true,
      recording: json['recording'] == true,
      transferAllowed: json['transfer_allowed'] == true,
    );
  }

  static int _readSizeBytes(Map<String, dynamic> json) {
    final rawBytes = json['size_bytes'];
    if (rawBytes is int) {
      return rawBytes;
    }
    if (rawBytes is num) {
      return rawBytes.toInt();
    }

    final rawGb = json['size_gb'];
    if (rawGb is num) {
      return (rawGb.toDouble() * 1024 * 1024 * 1024).round();
    }

    return 0;
  }

  String get formattedSize {
    if (sizeBytes >= 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }

    if (sizeBytes >= 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }

    if (sizeBytes >= 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }

    if (sizeBytes > 0) {
      return '$sizeBytes B';
    }

    return '< 1 KB';
  }
}

class BagBrowserHeader extends StatelessWidget {
  const BagBrowserHeader({
    super.key,
    required this.ui,
    required this.loading,
    required this.onRefresh,
  });

  final BagUiScale ui;
  final bool loading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.folder_outlined, size: ui.icon),
        SizedBox(width: ui.gap),
        Expanded(
          child: Text(
            'Available Bags',
            style: TextStyle(
              fontSize: ui.title,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(
          height: ui.buttonHeight,
          child: OutlinedButton.icon(
            onPressed: loading ? null : onRefresh,
            icon: Icon(Icons.refresh, size: ui.icon),
            label: Text(
              'Refresh',
              style: TextStyle(fontSize: ui.caption),
            ),
          ),
        ),
      ],
    );
  }
}

class BagList extends StatelessWidget {
  const BagList({
    super.key,
    required this.ui,
    required this.bags,
    required this.selectedBag,
    required this.onSelected,
  });

  final BagUiScale ui;
  final List<BagInfo> bags;
  final BagInfo? selectedBag;
  final ValueChanged<BagInfo> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: bags.map((bag) {
        return Padding(
          padding: EdgeInsets.only(top: ui.gap),
          child: BagTile(
            ui: ui,
            bag: bag,
            selected: selectedBag?.name == bag.name,
            onTap: () => onSelected(bag),
          ),
        );
      }).toList(),
    );
  }
}

class BagTile extends StatelessWidget {
  const BagTile({
    super.key,
    required this.ui,
    required this.bag,
    required this.selected,
    required this.onTap,
  });

  final BagUiScale ui;
  final BagInfo bag;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = bag.recording
        ? Colors.redAccent
        : bag.transferAllowed
            ? Colors.greenAccent
            : Colors.orangeAccent;

    final borderColor = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).dividerColor.withValues(alpha: 0.5);

    final backgroundColor = selected
        ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.22)
        : Colors.transparent;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.all(ui.innerPadding),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: borderColor,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.circle, color: statusColor, size: ui.icon),
            SizedBox(width: ui.gap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          bag.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: ui.body,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (bag.latest) ...[
                        const SizedBox(width: 6),
                        BagBadge(label: 'Latest', ui: ui),
                      ],
                      if (bag.recording) ...[
                        const SizedBox(width: 6),
                        BagBadge(label: 'Recording', ui: ui),
                      ],
                      if (selected) ...[
                        const SizedBox(width: 6),
                        BagBadge(label: 'Selected', ui: ui),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${bag.formattedSize}  •  ${bag.modified}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: ui.caption,
                      color: Colors.grey,
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

class SelectedBagPanel extends StatelessWidget {
  const SelectedBagPanel({
    super.key,
    required this.ui,
    required this.bag,
    required this.onClear,
  });

  final BagUiScale ui;
  final BagInfo? bag;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final selected = bag;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(ui.innerPadding),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.35),
        border: Border.all(
          color: selected == null
              ? Theme.of(context).dividerColor.withValues(alpha: 0.5)
              : Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
          width: selected == null ? 1 : 2,
        ),
      ),
      child: selected == null
          ? _EmptySelectedBag(ui: ui)
          : _SelectedBagDetails(
              ui: ui,
              bag: selected,
              onClear: onClear,
            ),
    );
  }
}

class _EmptySelectedBag extends StatelessWidget {
  const _EmptySelectedBag({
    required this.ui,
  });

  final BagUiScale ui;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.touch_app_outlined, size: ui.icon, color: Colors.grey),
        SizedBox(width: ui.gap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Selected Bag',
                style: TextStyle(
                  fontSize: ui.subtitle,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'No bag selected. Select a bag from the list below.',
                style: TextStyle(
                  fontSize: ui.caption,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SelectedBagDetails extends StatelessWidget {
  const _SelectedBagDetails({
    required this.ui,
    required this.bag,
    required this.onClear,
  });

  final BagUiScale ui;
  final BagInfo bag;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final canTransfer = bag.transferAllowed && !bag.recording;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.folder_open, size: ui.icon),
            SizedBox(width: ui.gap),
            Expanded(
              child: Text(
                'Selected Bag',
                style: TextStyle(
                  fontSize: ui.subtitle,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (bag.latest) BagBadge(label: 'Latest', ui: ui),
            if (bag.recording) ...[
              const SizedBox(width: 6),
              BagBadge(label: 'Recording', ui: ui),
            ],
          ],
        ),
        SizedBox(height: ui.gap),
        Text(
          bag.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: ui.body,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${bag.formattedSize}  •  ${bag.modified}',
          style: TextStyle(
            fontSize: ui.caption,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          bag.path,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: ui.caption,
            color: Colors.grey,
          ),
        ),
        SizedBox(height: ui.gap),
        Row(
          children: [
            Expanded(
              child: Text(
                bag.recording
                    ? 'This bag is currently recording and cannot be transferred yet.'
                    : canTransfer
                        ? 'Transfer options will be added next.'
                        : 'Transfer is disabled for this bag.',
                style: TextStyle(
                  fontSize: ui.caption,
                  color: bag.recording ? Colors.redAccent : Colors.grey,
                ),
              ),
            ),
            SizedBox(width: ui.gap),
            SizedBox(
              height: ui.buttonHeight,
              child: OutlinedButton.icon(
                onPressed: onClear,
                icon: Icon(Icons.close, size: ui.icon),
                label: Text(
                  'Clear',
                  style: TextStyle(fontSize: ui.caption),
                ),
              ),
            ),
            SizedBox(width: ui.gap),
            SizedBox(
              height: ui.buttonHeight,
              child: ElevatedButton.icon(
                onPressed: null,
                icon: Icon(Icons.drive_folder_upload, size: ui.icon),
                label: Text(
                  'Transfer',
                  style: TextStyle(fontSize: ui.caption),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class BagBadge extends StatelessWidget {
  const BagBadge({
    super.key,
    required this.label,
    required this.ui,
  });

  final String label;
  final BagUiScale ui;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context).colorScheme.primaryContainer,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: ui.caption - 1,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class BagErrorBox extends StatelessWidget {
  const BagErrorBox({
    super.key,
    required this.ui,
    required this.message,
    required this.onRetry,
  });

  final BagUiScale ui;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.error_outline, color: Colors.redAccent, size: ui.icon),
        SizedBox(width: ui.gap),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              fontSize: ui.caption,
              color: Colors.redAccent,
            ),
          ),
        ),
        TextButton(
          onPressed: onRetry,
          child: const Text('Retry'),
        ),
      ],
    );
  }
}

class BagUiScale {
  BagUiScale(BuildContext context) {
    final size = MediaQuery.of(context).size;
    compact = size.height < 950 || size.width < 1500;

    cardPadding = compact ? 10 : 18;
    innerPadding = compact ? 8 : 12;
    gap = compact ? 8 : 14;
    sectionGap = compact ? 14 : 20;
    title = compact ? 16 : 22;
    subtitle = compact ? 14 : 18;
    body = compact ? 13 : 16;
    caption = compact ? 11 : 13;
    icon = compact ? 13 : 17;
    buttonHeight = compact ? 30 : 38;
  }

  late final bool compact;
  late final double cardPadding;
  late final double innerPadding;
  late final double gap;
  late final double sectionGap;
  late final double title;
  late final double subtitle;
  late final double body;
  late final double caption;
  late final double icon;
  late final double buttonHeight;
}