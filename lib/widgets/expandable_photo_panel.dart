import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Collapsed photos keep a two-row viewport; expanded photos join page scrolling.
class ExpandablePhotoPanel extends StatefulWidget {
  final int itemCount;
  final int minimumRows;
  final double spacing;
  final Widget Function(BuildContext context, bool expanded) builder;

  const ExpandablePhotoPanel({
    super.key,
    required this.itemCount,
    required this.builder,
    this.minimumRows = 1,
    this.spacing = 8,
  });

  @override
  State<ExpandablePhotoPanel> createState() => _ExpandablePhotoPanelState();
}

class _ExpandablePhotoPanelState extends State<ExpandablePhotoPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final totalRows = math.max(
      widget.minimumRows,
      (widget.itemCount / 3).ceil(),
    );
    final expanded = _expanded && totalRows > 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (totalRows > 2)
          TextButton.icon(
            onPressed: () => setState(() => _expanded = !expanded),
            icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
            label: Text(expanded ? '收起图片列表' : '展开图片列表'),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            final tile = math.max(
              .1,
              (constraints.maxWidth - widget.spacing * 2) / 3,
            );
            final rows = expanded ? totalRows : math.min(2, totalRows);
            return SizedBox(
              height: tile * rows + widget.spacing * math.max(0, rows - 1),
              child: widget.builder(context, expanded),
            );
          },
        ),
      ],
    );
  }
}
