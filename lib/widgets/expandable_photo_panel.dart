import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Collapsed photos keep a two-row viewport; expanded photos join page scrolling.
class ExpandablePhotoPanel extends StatelessWidget {
  final int itemCount;
  final int minimumRows;
  final double spacing;
  final bool expanded;
  final Widget Function(BuildContext context, bool expanded) builder;

  const ExpandablePhotoPanel({
    super.key,
    required this.itemCount,
    required this.builder,
    this.minimumRows = 1,
    this.spacing = 8,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final totalRows = math.max(minimumRows, (itemCount / 3).ceil());
    final showAllRows = expanded && totalRows > 2;
    return LayoutBuilder(
      builder: (context, constraints) {
        final tile = math.max(.1, (constraints.maxWidth - spacing * 2) / 3);
        final rows = showAllRows ? totalRows : math.min(2, totalRows);
        return SizedBox(
          height: tile * rows + spacing * math.max(0, rows - 1),
          child: builder(context, showAllRows),
        );
      },
    );
  }
}
