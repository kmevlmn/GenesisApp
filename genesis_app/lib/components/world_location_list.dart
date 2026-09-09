import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../icons/custom_icon_assets.dart';
import '../ui/components/recent_chat_marker.dart';
import '../ui/components/genesis_list_image.dart';
import '../ui/tokens/genesis_image_radii.dart';
import '../ui/tokens/genesis_colors.dart';
import '../utils/genesis_image_resource.dart';
import 'world_details_shell.dart';
import 'world_new_badge.dart';
import 'world_point.dart';

const String _locationDefaultImageAsset =
    'assets/images/map_default/location_default.webp';
const double worldLocationCoverLogicalSize = 64;

typedef WorldLocationNodeHeaderBuilder =
    Widget? Function(BuildContext context, WorldPoint point, int level);
typedef WorldLocationNodeFooterBuilder =
    Widget? Function(BuildContext context, WorldPoint point, int level);

enum _WorldLocationListRowKind { flatPoint, nodeHeader, nodeFooter }

class _WorldLocationListRow {
  const _WorldLocationListRow._({
    required this.kind,
    required this.point,
    required this.level,
    this.node,
    this.showDivider = false,
  });

  const _WorldLocationListRow.flatPoint(
    WorldPoint point, {
    required bool showDivider,
  }) : this._(
         kind: _WorldLocationListRowKind.flatPoint,
         point: point,
         level: 0,
         showDivider: showDivider,
       );

  _WorldLocationListRow.nodeHeader(WorldMapLocationNode node, int level)
    : this._(
        kind: _WorldLocationListRowKind.nodeHeader,
        point: node.point,
        node: node,
        level: level,
      );

  _WorldLocationListRow.nodeFooter(WorldMapLocationNode node, int level)
    : this._(
        kind: _WorldLocationListRowKind.nodeFooter,
        point: node.point,
        node: node,
        level: level,
      );

  final _WorldLocationListRowKind kind;
  final WorldPoint point;
  final WorldMapLocationNode? node;
  final int level;
  final bool showDivider;
}

class WorldLocationList extends StatefulWidget {
  const WorldLocationList({
    super.key,
    required this.points,
    this.controller,
    this.locationNodes = const <WorldMapLocationNode>[],
    this.physics,
    this.enableOuterScrollHandoff = true,
    this.lazyBuildRows = false,
    this.padding = const EdgeInsets.fromLTRB(12, 8, 12, 12),
    this.recentChatLocationIds = const <String>{},
    this.onPointTap,
    this.onNodeHeaderTap,
    this.nodeHeaderBuilder,
    this.nodeFooterBuilder,
    this.header,
    this.footer,
  });

  final List<WorldPoint> points;
  final ScrollController? controller;
  final List<WorldMapLocationNode> locationNodes;
  final ScrollPhysics? physics;
  final bool enableOuterScrollHandoff;
  final bool lazyBuildRows;
  final EdgeInsetsGeometry padding;
  final Set<String> recentChatLocationIds;
  final ValueChanged<WorldPoint>? onPointTap;
  final ValueChanged<WorldPoint>? onNodeHeaderTap;
  final WorldLocationNodeHeaderBuilder? nodeHeaderBuilder;
  final WorldLocationNodeFooterBuilder? nodeFooterBuilder;
  final Widget? header;
  final Widget? footer;

  @override
  State<WorldLocationList> createState() => _WorldLocationListState();
}

class _WorldLocationListState extends State<WorldLocationList> {
  late ScrollController _listController;
  late bool _ownsListController;
  ScrollController? _outerController;
  bool _outerPageAtTop = true;
  bool _pointerActive = false;
  bool _needsPhysicsRebuild = false;
  bool _draggedOuterDuringPointer = false;
  VelocityTracker? _velocityTracker;

  static const double _ballisticHandoffMinVelocity = 80;
  static const double _ballisticHandoffDistanceFactor = 0.18;

  @override
  void initState() {
    super.initState();
    _setListController(widget.controller);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _setOuterController(
      widget.enableOuterScrollHandoff
          ? WorldDetailsPanelScrollControllerScope.maybeOf(context)
          : null,
    );
  }

  @override
  void didUpdateWidget(covariant WorldLocationList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      final oldController = _listController;
      final ownedOldController = _ownsListController;
      _setListController(widget.controller);
      if (ownedOldController) oldController.dispose();
    }
    if (oldWidget.enableOuterScrollHandoff != widget.enableOuterScrollHandoff) {
      _setOuterController(
        widget.enableOuterScrollHandoff
            ? WorldDetailsPanelScrollControllerScope.maybeOf(context)
            : null,
      );
    }
  }

  @override
  void dispose() {
    _outerController?.removeListener(_handleOuterScroll);
    if (_ownsListController) _listController.dispose();
    super.dispose();
  }

  void _setListController(ScrollController? controller) {
    _ownsListController = controller == null;
    _listController = controller ?? ScrollController();
  }

  @override
  Widget build(BuildContext context) {
    final outerController = _outerController;
    final rows = widget.lazyBuildRows
        ? (widget.locationNodes.isNotEmpty
              ? _flattenNodeRows(widget.locationNodes)
              : _flattenPointRows(widget.points))
        : const <_WorldLocationListRow>[];
    final headerOffset = widget.header == null ? 0 : 1;
    final itemCount =
        rows.length + headerOffset + (widget.footer == null ? 0 : 1);
    return Listener(
      onPointerDown: (event) {
        _pointerActive = true;
        _draggedOuterDuringPointer = false;
        _velocityTracker = VelocityTracker.withKind(event.kind)
          ..addPosition(event.timeStamp, event.localPosition);
      },
      onPointerUp: (_) {
        _applyOuterPointerFling();
        _finishPointer();
      },
      onPointerCancel: (_) {
        _finishPointer();
      },
      onPointerMove: (event) {
        _velocityTracker?.addPosition(event.timeStamp, event.localPosition);
        if (outerController == null ||
            !outerController.hasClients ||
            !widget.enableOuterScrollHandoff) {
          return;
        }

        final dragDelta = event.delta.dy;
        if (!_outerPageAtTop) {
          if (_applyOuterDrag(outerController, dragDelta)) {
            _draggedOuterDuringPointer = true;
          }
          return;
        }

        if (!_listController.hasClients) return;
        final position = _listController.position;
        final atBottom = position.extentAfter <= 0.5;
        final atTop = position.extentBefore <= 0.5;
        final draggingPastBottom = dragDelta < 0 && atBottom;
        final draggingPastTop = dragDelta > 0 && atTop;
        if (!draggingPastBottom && !draggingPastTop) return;
        if (_applyOuterDrag(outerController, dragDelta)) {
          _draggedOuterDuringPointer = true;
        }
      },
      child: NotificationListener<OverscrollNotification>(
        onNotification: (notification) {
          if (outerController == null ||
              !outerController.hasClients ||
              !widget.enableOuterScrollHandoff ||
              notification.metrics.axis != Axis.vertical) {
            return false;
          }
          if (!_outerPageAtTop) return false;

          final dragDelta = notification.dragDetails?.delta.dy;
          if (dragDelta != null) {
            return _applyOuterDrag(outerController, dragDelta);
          }
          return _applyOuterOverscroll(
            outerController,
            overscroll: notification.overscroll,
            velocity: notification.velocity,
          );
        },
        child: widget.lazyBuildRows
            ? ListView.builder(
                controller: _listController,
                physics: _listPhysics,
                padding: widget.padding,
                itemCount: itemCount,
                itemBuilder: (context, index) {
                  if (widget.header != null && index == 0) {
                    return widget.header!;
                  }
                  final rowIndex = index - headerOffset;
                  if (rowIndex >= rows.length) return widget.footer!;
                  return _buildRow(rows[rowIndex]);
                },
              )
            : ListView(
                controller: _listController,
                physics: _listPhysics,
                padding: widget.padding,
                children: [
                  if (widget.header != null) widget.header!,
                  if (widget.locationNodes.isNotEmpty)
                    ..._buildEagerNodeRows(widget.locationNodes)
                  else
                    ..._buildEagerFlatPointRows(widget.points),
                  if (widget.footer != null) widget.footer!,
                ],
              ),
      ),
    );
  }

  ScrollPhysics get _listPhysics {
    return widget.physics ??
        (_outerPageAtTop
            ? const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              )
            : const NeverScrollableScrollPhysics());
  }

  List<Widget> _buildEagerFlatPointRows(List<WorldPoint> points) {
    return [
      for (var index = 0; index < points.length; index++) ...[
        _PointListItem(
          point: points[index],
          level: points[index].depth,
          showRecentChatIcon: _pointMatchesLocationIds(
            points[index],
            widget.recentChatLocationIds,
          ),
          onTap: widget.onPointTap,
        ),
        if (index < points.length - 1) const Divider(height: 1),
      ],
    ];
  }

  List<Widget> _buildEagerNodeRows(List<WorldMapLocationNode> nodes) {
    return _buildEagerNodeRowsAtLevel(nodes, 0);
  }

  List<Widget> _buildEagerNodeRowsAtLevel(
    List<WorldMapLocationNode> nodes,
    int level,
  ) {
    final rows = <Widget>[];
    for (final node in nodes) {
      final hideSyntheticRootHeader =
          node.point.name.trim().isEmpty && node.children.isNotEmpty;
      if (hideSyntheticRootHeader) {
        rows.addAll(_buildEagerNodeRowsAtLevel(node.children, level));
        continue;
      }
      if (node.children.isEmpty && node.point.isLeafLocation) {
        final customHeader = widget.nodeHeaderBuilder?.call(
          context,
          node.point,
          level,
        );
        if (customHeader != null) {
          rows.add(customHeader);
          final customFooter = widget.nodeFooterBuilder?.call(
            context,
            node.point,
            level,
          );
          if (customFooter != null) rows.add(customFooter);
          continue;
        }
        rows.add(
          _LocationCard(
            point: node.point,
            targetPoint: node.chatTargetPoint ?? node.point,
            showRecentChatIcon: _nodeMatchesLocationIds(
              node,
              widget.recentChatLocationIds,
            ),
            level: level,
            indent: level * 15.0,
            onTap: widget.onPointTap,
          ),
        );
        continue;
      }
      final customHeader = widget.nodeHeaderBuilder?.call(
        context,
        node.point,
        level,
      );
      rows.add(
        customHeader ??
            _NodeHeader(
              point: node.point,
              level: level,
              showRecentChatIcon: _nodeMatchesLocationIds(
                node,
                widget.recentChatLocationIds,
              ),
              onTap: widget.onNodeHeaderTap,
            ),
      );
      rows.addAll(_buildEagerNodeRowsAtLevel(node.children, level + 1));
      final customFooter = widget.nodeFooterBuilder?.call(
        context,
        node.point,
        level,
      );
      if (customFooter != null) rows.add(customFooter);
    }
    return rows;
  }

  List<_WorldLocationListRow> _flattenPointRows(List<WorldPoint> points) {
    return List<_WorldLocationListRow>.generate(
      points.length,
      (index) => _WorldLocationListRow.flatPoint(
        points[index],
        showDivider: index < points.length - 1,
      ),
      growable: false,
    );
  }

  List<_WorldLocationListRow> _flattenNodeRows(
    List<WorldMapLocationNode> nodes,
  ) {
    final rows = <_WorldLocationListRow>[];
    _appendNodeRows(rows, nodes, 0);
    return rows;
  }

  void _appendNodeRows(
    List<_WorldLocationListRow> rows,
    List<WorldMapLocationNode> nodes,
    int level,
  ) {
    for (final node in nodes) {
      final hideSyntheticRootHeader =
          node.point.name.trim().isEmpty && node.children.isNotEmpty;
      if (hideSyntheticRootHeader) {
        _appendNodeRows(rows, node.children, level);
        continue;
      }
      rows.add(_WorldLocationListRow.nodeHeader(node, level));
      if (node.children.isEmpty) continue;
      _appendNodeRows(rows, node.children, level + 1);
      if (widget.nodeFooterBuilder != null) {
        rows.add(_WorldLocationListRow.nodeFooter(node, level));
      }
    }
  }

  Widget _buildRow(_WorldLocationListRow row) {
    if (row.kind == _WorldLocationListRowKind.flatPoint) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PointListItem(
            point: row.point,
            level: row.point.depth,
            showRecentChatIcon: _pointMatchesLocationIds(
              row.point,
              widget.recentChatLocationIds,
            ),
            onTap: widget.onPointTap,
          ),
          if (row.showDivider) const Divider(height: 1),
        ],
      );
    }

    final node = row.node!;
    if (row.kind == _WorldLocationListRowKind.nodeFooter) {
      return widget.nodeFooterBuilder?.call(context, row.point, row.level) ??
          const SizedBox.shrink();
    }

    final customHeader = widget.nodeHeaderBuilder?.call(
      context,
      row.point,
      row.level,
    );
    if (node.children.isEmpty && row.point.isLeafLocation) {
      if (customHeader != null) {
        final customFooter = widget.nodeFooterBuilder?.call(
          context,
          row.point,
          row.level,
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [customHeader, if (customFooter != null) customFooter],
        );
      }
      return _LocationCard(
        point: row.point,
        targetPoint: node.chatTargetPoint ?? row.point,
        showRecentChatIcon: _nodeMatchesLocationIds(
          node,
          widget.recentChatLocationIds,
        ),
        level: row.level,
        indent: row.level * 15.0,
        onTap: widget.onPointTap,
      );
    }
    return customHeader ??
        _NodeHeader(
          point: row.point,
          level: row.level,
          showRecentChatIcon: _nodeMatchesLocationIds(
            node,
            widget.recentChatLocationIds,
          ),
          onTap: widget.onNodeHeaderTap,
        );
  }

  void _setOuterController(ScrollController? controller) {
    if (_outerController == controller) return;
    _outerController?.removeListener(_handleOuterScroll);
    _outerController = controller;
    _outerController?.addListener(_handleOuterScroll);
    _syncOuterPageAtTopState(rebuild: false);
  }

  void _handleOuterScroll() {
    _syncOuterPageAtTopState(rebuild: !_pointerActive);
  }

  void _syncOuterPageAtTopState({required bool rebuild}) {
    final atTop = _isOuterPageAtTop;
    if (atTop == _outerPageAtTop) return;
    _outerPageAtTop = atTop;
    if (rebuild && mounted) {
      _needsPhysicsRebuild = false;
      setState(() {});
    } else {
      _needsPhysicsRebuild = true;
    }
  }

  void _finishPointer() {
    _pointerActive = false;
    _draggedOuterDuringPointer = false;
    _velocityTracker = null;
    _syncOuterPageAtTopState(rebuild: true);
    if (_needsPhysicsRebuild && mounted) {
      _needsPhysicsRebuild = false;
      setState(() {});
    }
  }

  void _applyOuterPointerFling() {
    final outerController = _outerController;
    final velocityTracker = _velocityTracker;
    if (!_draggedOuterDuringPointer ||
        outerController == null ||
        !outerController.hasClients ||
        velocityTracker == null) {
      return;
    }
    final velocity = velocityTracker.getVelocity().pixelsPerSecond.dy;
    if (velocity.abs() < _ballisticHandoffMinVelocity) return;
    _animateOuterScrollDelta(
      outerController,
      -velocity * _ballisticHandoffDistanceFactor,
    );
  }

  bool get _isOuterPageAtTop {
    final controller = _outerController;
    return controller == null ||
        !controller.hasClients ||
        controller.offset <= 0.5;
  }

  bool _applyOuterDrag(ScrollController outerController, double dragDelta) {
    if (dragDelta.abs() <= 0.5) return false;
    final before = outerController.offset;
    final target = (before - dragDelta)
        .clamp(0.0, outerController.position.maxScrollExtent)
        .toDouble();
    if ((target - before).abs() <= 0.5) return false;
    outerController.jumpTo(target);
    return true;
  }

  bool _applyOuterOverscroll(
    ScrollController outerController, {
    required double overscroll,
    required double velocity,
  }) {
    var handled = false;
    if (overscroll.abs() > 0.5) {
      handled = _applyOuterScrollDelta(outerController, overscroll);
    }
    if (velocity.abs() < _ballisticHandoffMinVelocity) return handled;
    final direction = overscroll.abs() > 0.5 ? overscroll.sign : velocity.sign;
    final distance =
        (velocity.abs() * _ballisticHandoffDistanceFactor).clamp(24.0, 420.0) *
        direction;
    return _animateOuterScrollDelta(outerController, distance) || handled;
  }

  bool _applyOuterScrollDelta(
    ScrollController outerController,
    double scrollDelta,
  ) {
    if (scrollDelta.abs() <= 0.5) return false;
    final before = outerController.offset;
    final target = (before + scrollDelta)
        .clamp(0.0, outerController.position.maxScrollExtent)
        .toDouble();
    if ((target - before).abs() <= 0.5) return false;
    outerController.jumpTo(target);
    return true;
  }

  bool _animateOuterScrollDelta(
    ScrollController outerController,
    double scrollDelta,
  ) {
    if (scrollDelta.abs() <= 0.5) return false;
    final before = outerController.offset;
    final target = (before + scrollDelta)
        .clamp(0.0, outerController.position.maxScrollExtent)
        .toDouble();
    if ((target - before).abs() <= 0.5) return false;
    unawaited(
      outerController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.decelerate,
      ),
    );
    return true;
  }
}

class _PointListItem extends StatelessWidget {
  const _PointListItem({
    required this.point,
    required this.level,
    required this.showRecentChatIcon,
    required this.onTap,
  });

  final WorldPoint point;
  final int level;
  final bool showRecentChatIcon;
  final ValueChanged<WorldPoint>? onTap;

  @override
  Widget build(BuildContext context) {
    final depthIndent = point.depth < 0 ? 0.0 : point.depth * 15.0;
    final description = point.locationDescription.trim();
    return InkWell(
      onTap: onTap == null ? null : () => onTap!(point),
      child: Padding(
        padding: EdgeInsets.only(left: depthIndent, top: 5, bottom: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PointListCover(point: point),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.place_outlined,
                        size: 14,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? GenesisColors.darkTextSecondary
                            : Colors.black,
                      ),
                      const SizedBox(width: 2),
                      Flexible(
                        fit: FlexFit.loose,
                        child: Text(
                          point.name,
                          style: _locationNameStyle(context, level),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (showRecentChatIcon) ...[
                        const SizedBox(width: 5),
                        const RecentChatIcon(),
                      ],
                      if (point.isNew &&
                          point.isLeafLocation &&
                          point.depth == 3) ...[
                        const SizedBox(width: 5),
                        WorldNewBadge(
                          key: ValueKey<String>(
                            'world-location-new-badge-${point.id}',
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: level >= 2 ? 8 : 4),
                  if (point.users.isNotEmpty)
                    _PointCharacterGroups(users: point.users),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _PointSummaryRow(description: description),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NodeHeader extends StatelessWidget {
  const _NodeHeader({
    required this.point,
    required this.level,
    required this.showRecentChatIcon,
    required this.onTap,
  });

  final WorldPoint point;
  final int level;
  final bool showRecentChatIcon;
  final ValueChanged<WorldPoint>? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap == null ? null : () => onTap!(point),
      child: Padding(
        padding: EdgeInsets.fromLTRB(level * 15.0, 5, 0, 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              fit: FlexFit.loose,
              child: Text(
                '- ${point.name}',
                style: _locationNameStyle(context, level),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (showRecentChatIcon) ...[
              const SizedBox(width: 5),
              const RecentChatIcon(),
            ],
            if (point.isNew && point.isLeafLocation && point.depth == 3) ...[
              const SizedBox(width: 5),
              WorldNewBadge(
                key: ValueKey<String>('world-location-new-badge-${point.id}'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.point,
    required this.targetPoint,
    required this.showRecentChatIcon,
    required this.level,
    required this.indent,
    required this.onTap,
  });

  final WorldPoint point;
  final WorldPoint targetPoint;
  final bool showRecentChatIcon;
  final int level;
  final double indent;
  final ValueChanged<WorldPoint>? onTap;

  @override
  Widget build(BuildContext context) {
    final description = point.locationDescription.trim();
    return InkWell(
      key: ValueKey<String>('world-location-card-${point.id}'),
      onTap: onTap == null ? null : () => onTap!(targetPoint),
      child: Padding(
        padding: EdgeInsets.only(left: indent, top: 5, bottom: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LocationCardCover(point: point),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.place_outlined,
                        size: 14,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? GenesisColors.darkTextSecondary
                            : Colors.black,
                      ),
                      const SizedBox(width: 2),
                      Flexible(
                        fit: FlexFit.loose,
                        child: Text(
                          point.name,
                          style: _locationNameStyle(context, level),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (showRecentChatIcon) ...[
                        const SizedBox(width: 5),
                        const RecentChatIcon(),
                      ],
                      if (point.isNew &&
                          point.isLeafLocation &&
                          point.depth == 3) ...[
                        const SizedBox(width: 5),
                        WorldNewBadge(
                          key: ValueKey<String>(
                            'world-location-new-badge-${point.id}',
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: level >= 2 ? 8 : 4),
                  if (point.users.isNotEmpty)
                    _PointCharacterGroups(users: point.users),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _PointSummaryRow(description: description),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

TextStyle _locationNameStyle(BuildContext context, int level) {
  if (level <= 0) {
    return TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: Theme.of(context).brightness == Brightness.dark
          ? GenesisColors.darkTextPrimary
          : Colors.black,
    );
  }
  return TextStyle(
    fontSize: 14,
    height: 1.2,
    fontWeight: level == 1 ? FontWeight.w600 : FontWeight.w400,
    color: Theme.of(context).brightness == Brightness.dark
        ? GenesisColors.darkTextPrimary
        : Colors.black,
  );
}

bool _pointMatchesLocationIds(WorldPoint point, Set<String> locationIds) {
  if (locationIds.isEmpty) return false;
  final locationId = point.sceneId.trim();
  return locationId.isNotEmpty && locationIds.contains(locationId);
}

bool _nodeMatchesLocationIds(
  WorldMapLocationNode node,
  Set<String> locationIds,
) {
  if (locationIds.isEmpty) return false;
  final locationId = node.id.trim();
  if (locationId.isNotEmpty && locationIds.contains(locationId)) return true;
  return _pointMatchesLocationIds(node.point, locationIds);
}

class _PointCharacterGroups extends StatelessWidget {
  const _PointCharacterGroups({required this.users});

  final List<UserAvatar> users;

  @override
  Widget build(BuildContext context) {
    final namedUsers = users
        .where((user) => _characterName(user).isNotEmpty)
        .toList(growable: false);
    final aiUsers = <UserAvatar>[
      ...namedUsers.where((user) => user.showStar && !user.isNew),
      ...namedUsers.where((user) => user.showStar && user.isNew),
    ];
    final nonAiUsers = <UserAvatar>[
      ...namedUsers.where((user) => !user.showStar && !user.isNew),
      ...namedUsers.where((user) => !user.showStar && user.isNew),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (aiUsers.isNotEmpty)
          _PointCharacterGroupRow(
            iconAsset: characterStatIconAsset,
            users: aiUsers,
          ),
        if (aiUsers.isNotEmpty && nonAiUsers.isNotEmpty)
          const SizedBox(height: 2),
        if (nonAiUsers.isNotEmpty)
          _PointCharacterGroupRow(
            iconAsset: characterStatIconAsset,
            users: nonAiUsers,
          ),
      ],
    );
  }

  String _characterName(UserAvatar user) {
    return (user.name ?? user.initials).trim();
  }
}

class _PointCharacterGroupRow extends StatelessWidget {
  const _PointCharacterGroupRow({required this.iconAsset, required this.users});

  static const _fontSize = 12.0;
  static const _lineHeight = 1.4;

  final String iconAsset;
  final List<UserAvatar> users;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 12,
          height:
              MediaQuery.textScalerOf(context).scale(_fontSize) * _lineHeight,
          child: Align(
            alignment: Alignment.center,
            child: SvgPicture.asset(
              iconAsset,
              colorFilter: Theme.of(context).brightness == Brightness.dark
                  ? const ColorFilter.mode(
                      GenesisColors.darkTextSecondary,
                      BlendMode.srcIn,
                    )
                  : null,
              width: 12,
              height: 12,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text.rich(
            TextSpan(children: _characterSpans()),
            style: TextStyle(
              fontSize: _fontSize,
              height: _lineHeight,
              fontWeight: FontWeight.w400,
              color: Theme.of(context).brightness == Brightness.dark
                  ? GenesisColors.darkTextPrimary
                  : Colors.black,
            ),
          ),
        ),
      ],
    );
  }

  List<InlineSpan> _characterSpans() {
    final spans = <InlineSpan>[];
    for (var index = 0; index < users.length; index += 1) {
      final user = users[index];
      final name = (user.name ?? user.initials).trim();
      spans.add(TextSpan(text: name));
      if (user.isNew) {
        final stableId = user.id.trim().isNotEmpty ? user.id.trim() : name;
        spans
          ..add(const WidgetSpan(child: SizedBox(width: 4)))
          ..add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: WorldNewBadge(
                key: ValueKey<String>(
                  'world-location-character-new-badge-$stableId',
                ),
              ),
            ),
          );
      }
      if (index < users.length - 1) {
        if (user.isNew) {
          spans.add(const WidgetSpan(child: SizedBox(width: 4)));
        }
        spans.add(const TextSpan(text: ', '));
      }
    }
    return spans;
  }
}

class _PointSummaryRow extends StatelessWidget {
  const _PointSummaryRow({required this.description});

  final String description;

  @override
  Widget build(BuildContext context) {
    return Text(
      description,
      style: TextStyle(
        fontSize: 12,
        height: 1.25,
        fontWeight: FontWeight.w400,
        color: Theme.of(context).brightness == Brightness.dark
            ? GenesisColors.darkTextSecondary
            : Colors.black,
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _PointListCover extends StatelessWidget {
  const _PointListCover({required this.point});

  final WorldPoint point;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: worldLocationCoverLogicalSize,
      height: worldLocationCoverLogicalSize,
      child: _LocationCoverImage(point: point),
    );
  }
}

class _LocationCardCover extends StatelessWidget {
  const _LocationCardCover({required this.point});

  final WorldPoint point;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: worldLocationCoverLogicalSize,
      height: worldLocationCoverLogicalSize,
      child: _LocationCoverImage(point: point),
    );
  }
}

class _LocationCoverImage extends StatelessWidget {
  const _LocationCoverImage({required this.point});

  final WorldPoint point;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final logicalWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : worldLocationCoverLogicalSize;
        final logicalHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : worldLocationCoverLogicalSize;
        final localBytes = point.iconBytes;
        if (localBytes != null && localBytes.isNotEmpty) {
          final cacheWidth =
              (logicalWidth * MediaQuery.devicePixelRatioOf(context)).round();
          return ClipRRect(
            borderRadius: GenesisImageRadii.content,
            child: Image.memory(
              localBytes,
              key: ValueKey<String>('world-location-memory-image-${point.id}'),
              width: logicalWidth,
              height: logicalHeight,
              fit: BoxFit.cover,
              cacheWidth: cacheWidth,
              gaplessPlayback: true,
            ),
          );
        }
        final rawUrl = point.iconUrl.trim();
        final resizedUrl = resizeGenesisImageUrl(
          rawUrl,
          logicalWidth: logicalWidth,
          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        );
        final imageUrl = rawUrl.isEmpty
            ? _locationDefaultImageAsset
            : (resizedUrl.isNotEmpty ? resizedUrl : rawUrl);
        final dark = Theme.of(context).brightness == Brightness.dark;
        final image = GenesisListImage(
          imageUrl: imageUrl,
          width: logicalWidth,
          height: logicalHeight,
          placeholderAsset: _locationDefaultImageAsset,
          placeholder: dark
              ? const ColoredBox(color: GenesisColors.darkFaintFill)
              : null,
        );
        if (!dark || imageUrl != _locationDefaultImageAsset) return image;
        return DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: GenesisImageRadii.content,
            border: Border.all(
              color: GenesisColors.darkFaintFill.withValues(alpha: 0.06),
            ),
          ),
          child: image,
        );
      },
    );
  }
}
