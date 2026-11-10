import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_ui/redefine_ui.dart';

import 'logic.dart';

/// One card of the property strip: a property, or the trailing "Add" card.
class PropertyTab extends StatelessWidget {
  const PropertyTab({
    super.key,
    required this.name,
    required this.illustration,
    required this.onTap,
    this.selected = false,
    this.attention = false,
  }) : isAdd = false;

  const PropertyTab.add({super.key, required this.onTap})
    : name = 'Add property',
      illustration = '',
      selected = false,
      attention = false,
      isAdd = true;

  final String name, illustration;
  final VoidCallback onTap;
  final bool selected, isAdd;

  /// Shows the lime dot: a quote to answer or a job under way.
  final bool attention;

  static const _width = 96.0;
  static const _height = 100.0;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(14);
    final label = GoogleFonts.plusJakartaSans(
      fontSize: 11,
      fontWeight: isAdd ? FontWeight.w500 : FontWeight.w600,
      color: isAdd
          ? const Color(0xFF888888)
          : selected
          ? RColors.tealDeep
          : const Color(0xFF555555),
    );
    final card = Container(
      width: _width,
      height: _height,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: selected ? RColors.tealTint : Colors.transparent,
        borderRadius: shape,
        border: Border.all(
          color: isAdd
              ? const Color(0xFFC5C2B9)
              : selected
              ? RColors.teal
              : RColors.border,
          width: isAdd
              ? 1
              : selected
              ? 1.5
              : 0.6,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isAdd)
            Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(color: RColors.paper2, shape: BoxShape.circle),
              child: const Icon(Icons.add, size: 16, color: RColors.inkMuted),
            )
          else
            Icon(illustrationIcon(illustration), size: 46, color: illustrationColor(illustration)),
          SizedBox(height: isAdd ? 6 : 4),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: label,
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      selected: isAdd ? null : selected,
      child: Tooltip(
        message: name,
        waitDuration: const Duration(milliseconds: 600),
        child: InkWell(
          onTap: onTap,
          borderRadius: shape,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              card,
              if (attention)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: RColors.lime,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? RColors.tealTint : RColors.surface,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The horizontal strip of the customer's properties, ending in "Add".
///
/// More tabs than fit scroll sideways. The selected tab is brought into view
/// whenever the selection changes, and a thin scrollbar under the tabs shows
/// that there are more, for a mouse has no other hint of it.
class PropertyTabStrip extends StatefulWidget {
  const PropertyTabStrip({
    super.key,
    required this.properties,
    required this.selectedId,
    required this.attention,
    required this.onSelect,
    required this.onAdd,
  });

  final List<Property> properties;
  final String? selectedId;

  /// Whether a property's tab carries the lime dot.
  final bool Function(Property property) attention;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;

  /// The band under the tabs that the scrollbar sits in.
  static const scrollbarBand = 10.0;
  static const height = PropertyTab._height + scrollbarBand;

  @override
  State<PropertyTabStrip> createState() => _PropertyTabStripState();
}

class _PropertyTabStripState extends State<PropertyTabStrip> {
  final _scroll = ScrollController();
  final _tabKeys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _revealSelected(animate: false);
  }

  @override
  void didUpdateWidget(PropertyTabStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    _tabKeys.removeWhere((id, _) => !widget.properties.any((p) => p.id == id));
    if (widget.selectedId != oldWidget.selectedId) _revealSelected();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Scrolls the strip, and only the strip, until the selected tab is in
  /// view; it has to be laid out first.
  void _revealSelected({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final tab = _tabKeys[widget.selectedId]?.currentContext?.findRenderObject();
      if (tab == null || !_scroll.hasClients) return;
      _scroll.position.ensureVisible(
        tab,
        alignment: 0.5,
        duration: animate ? const Duration(milliseconds: 250) : Duration.zero,
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: PropertyTabStrip.height,
      child: Scrollbar(
        controller: _scroll,
        thumbVisibility: true,
        thickness: 4,
        radius: const Radius.circular(2),
        child: SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(18, 0, 18, PropertyTabStrip.scrollbarBand),
          child: Row(
            children: [
              for (final p in widget.properties)
                Padding(
                  key: _tabKeys.putIfAbsent(p.id, GlobalKey.new),
                  padding: const EdgeInsets.only(right: 8),
                  child: PropertyTab(
                    name: p.name,
                    illustration: p.illustration,
                    selected: p.id == widget.selectedId,
                    attention: widget.attention(p),
                    onTap: () => widget.onSelect(p.id),
                  ),
                ),
              PropertyTab.add(onTap: widget.onAdd),
            ],
          ),
        ),
      ),
    );
  }
}

/// How a job's payment stands. As [RPaymentPill], except for a cancelled job
/// whose hold has yet to be released, which that pill would call "Hold placed".
class JobPaymentPill extends StatelessWidget {
  const JobPaymentPill(this.job, {super.key});
  final Job job;

  @override
  Widget build(BuildContext context) => holdBeingReleased(job)
      ? const RPill('Releasing hold', bg: RColors.paper2, fg: RColors.inkMuted)
      : RPaymentPill(job.payment);
}

/// A part of a screen fed by its own [RLiveController], for use inside another
/// scroll view (where an [RLive] cannot go): a spinner while it first loads,
/// the error with Retry when that fails, then [builder].
class LiveSection<T> extends StatelessWidget {
  const LiveSection({super.key, required this.controller, required this.builder});
  final RLiveController<T> controller;
  final Widget Function(BuildContext context, T data) builder;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (controller.hasData) return builder(context, controller.data as T);
      final error = controller.error;
      if (error != null && !controller.loading) {
        return RBanner(
          friendlyError(error),
          error: true,
          actionLabel: 'Retry',
          onAction: controller.refresh,
        );
      }
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: RColors.teal),
          ),
        ),
      );
    },
  );
}

/// The frame of a pushed screen: a back row, the body, and an optional
/// button bar pinned to the bottom.
class PushedScreen extends StatelessWidget {
  const PushedScreen({super.key, required this.child, this.backLabel = 'Back', this.bottom});

  final Widget child;
  final String backLabel;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final bottom = this.bottom;
    return Scaffold(
      backgroundColor: RColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 22, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                // maybePop, so that a screen with steps can take the back itself.
                child: RBackRow(backLabel, onTap: () => Navigator.of(context).maybePop()),
              ),
            ),
            Expanded(child: child),
            if (bottom != null)
              Padding(padding: const EdgeInsets.fromLTRB(22, 8, 22, 16), child: bottom),
          ],
        ),
      ),
    );
  }
}

/// A label on the left and its value (or any widget) on the right.
class DetailRow extends StatelessWidget {
  const DetailRow(this.label, {super.key, this.value = '', this.trailing, this.strong = false});
  final String label, value;
  final Widget? trailing;

  /// For the row that sums the others up.
  final bool strong;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Text(label, style: strong ? RText.title : RText.muted),
        const SizedBox(width: 16),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child:
                trailing ??
                Text(value, textAlign: TextAlign.right, style: strong ? RText.price : RText.body),
          ),
        ),
      ],
    ),
  );
}

/// The hairline between the rows of a card.
class RowDivider extends StatelessWidget {
  const RowDivider({super.key});

  @override
  Widget build(BuildContext context) =>
      const Divider(height: 9, thickness: 0.6, color: RColors.borderSoft);
}
