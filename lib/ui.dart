/// Ready-made UI for BIST: [BistPanel] (scripts + reports) and [BistPanel.overlay] (a floating button that opens the panel).
library;

import 'package:flutter/material.dart';

import 'flutter_bist.dart';

/// Lists the loaded scripts (▶ runs a node) and the run reports. Plain Material, works in any app.
class BistPanel extends StatelessWidget {
  /// Called before a run starts (e.g. close the panel so the app screen is visible)
  final VoidCallback? onRun;

  /// Shown as a close button in the header
  final VoidCallback? onClose;

  const BistPanel({super.key, this.onRun, this.onClose});

  /// For `MaterialApp.builder`: the app plus a small draggable "BIST" button that opens the panel above it.
  /// Shown when [enabled] (default: debug / profile builds).
  static Widget overlay(BuildContext context, Widget? child, {bool? enabled}) =>
      _BistOverlay(enabled: enabled ?? !const bool.fromEnvironment('dart.vm.product'), child: child);

  Future<void> _run(TestCase c) async {
    onRun?.call();
    await Bist.instance.run(c);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Material(
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: TabBar(
                    tabs: [
                      Tab(text: 'Scripts'),
                      Tab(text: 'Reports'),
                    ],
                  ),
                ),
                if (onClose != null) IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: onClose),
              ],
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: Bist.instance,
                builder: (context, _) => TabBarView(children: [_scripts(context), _reports(context)]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scripts(BuildContext context) {
    final roots = Bist.instance.scripts;
    if (roots.isEmpty) return const Center(child: Text('No scripts – Bist.instance.add(...) / loadAssets(...)'));
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [for (final r in roots) _CaseTile(c: r, onRun: _run)],
    );
  }

  Widget _reports(BuildContext context) {
    final reports = Bist.instance.reports;
    if (reports.isEmpty) return const Center(child: Text('No runs yet'));
    return ListView(children: [for (final r in reports) _ReportTile(report: r)]);
  }
}

class _StatusIcon extends StatelessWidget {
  final BistStatus status;

  const _StatusIcon(this.status);

  @override
  Widget build(BuildContext context) => status == BistStatus.running
      ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
      : Icon(status.icon, color: status.color, size: 18);
}

class _CaseTile extends StatelessWidget {
  final TestCase c;
  final Future<void> Function(TestCase c) onRun;

  const _CaseTile({required this.c, required this.onRun});

  @override
  Widget build(BuildContext context) {
    final bist = Bist.instance;
    final title = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${bist.numberOf(c)}. ',
            style: const TextStyle(color: Colors.grey),
          ),
          TextSpan(text: c.name),
          if (c.id != null)
            TextSpan(
              text: '  #${c.id}',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
        ],
      ),
    );
    final run = IconButton(
      tooltip: 'Run',
      icon: Icon(Icons.play_arrow_rounded, color: bist.isRunning ? Colors.grey : Colors.green),
      onPressed: bist.isRunning ? null : () => onRun(c),
    );
    final status = _StatusIcon(bist.lastStatus(c));
    if (c is TestUnit) {
      return ListTile(dense: true, leading: status, title: title, subtitle: c.manual == null ? null : Text('Manual: ${c.manual}'), trailing: run);
    }
    return ExpansionTile(
      dense: true,
      leading: status,
      title: title,
      trailing: run,
      childrenPadding: const EdgeInsets.only(left: 16),
      initiallyExpanded: c.parent == null,
      children: [for (final x in (c as TestGroup).cases) _CaseTile(c: x, onRun: onRun)],
    );
  }
}

class _ReportTile extends StatelessWidget {
  final BistReport report;

  const _ReportTile({required this.report});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: report,
      builder: (context, _) {
        final counts = [
          for (final s in BistStatus.values)
            if (report.count(s) > 0) '${report.count(s)} ${s.label.toLowerCase()}',
        ].join(', ');
        final t = report.time;
        String two(int n) => n.toString().padLeft(2, '0');
        return ExpansionTile(
          dense: true,
          leading: _StatusIcon(report.status),
          title: Text('${report.number}. ${report.target.name}'),
          subtitle: Text('${two(t.hour)}:${two(t.minute)}:${two(t.second)} · ${(report.duration.inMilliseconds / 1000).toStringAsFixed(1)} s · $counts'),
          childrenPadding: const EdgeInsets.only(left: 16),
          children: [for (final u in report.units) _UnitTile(u: u)],
        );
      },
    );
  }
}

class _UnitTile extends StatelessWidget {
  final BistUnitResult u;

  const _UnitTile({required this.u});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: u,
      builder: (context, _) => ExpansionTile(
        dense: true,
        leading: _StatusIcon(u.status),
        title: Text('${u.number}. ${u.unit.name}'),
        subtitle: u.error == null ? null : Text(u.error!, style: const TextStyle(color: Colors.red)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final s in u.steps)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text.rich(
                TextSpan(
                  style: const TextStyle(fontSize: 12),
                  children: [
                    TextSpan(
                      text: s.ok ? '✓ ' : '✗ ',
                      style: TextStyle(color: s.ok ? Colors.green : Colors.red),
                    ),
                    TextSpan(
                      text: '${s.label} ${s.cmd}  ',
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                    TextSpan(
                      text: '${s.ms} ms',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    if (s.error != null)
                      TextSpan(
                        text: '\n${s.error}',
                        style: const TextStyle(color: Colors.red),
                      ),
                    if (s.screen.isNotEmpty)
                      TextSpan(
                        text: '\nOn screen: ${s.screen.join(' | ')}',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    if (s.appErrors.isNotEmpty)
                      TextSpan(
                        text: '\nApp errors: ${s.appErrors.join(', ')}',
                        style: const TextStyle(color: Colors.orange),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BistOverlay extends StatefulWidget {
  final bool enabled;
  final Widget? child;

  const _BistOverlay({required this.enabled, required this.child});

  @override
  State<_BistOverlay> createState() => _BistOverlayState();
}

class _BistOverlayState extends State<_BistOverlay> {
  bool _open = false;
  Offset? _pos;
  late final _entry = OverlayEntry(builder: (context) => _layer(_currentPos(context)));

  Offset _currentPos(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return _pos ?? Offset(size.width - 72, size.height * .6);
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _entry.markNeedsBuild();
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child ?? const SizedBox.shrink();
    if (!widget.enabled) return child;
    // MaterialApp.builder sits above the Navigator: give the panel its own Overlay (tooltips, menus need one)
    return Stack(
      children: [
        child,
        Positioned.fill(child: Overlay(initialEntries: [_entry])),
      ],
    );
  }

  Widget _layer(Offset pos) {
    return Stack(
      children: [
        if (_open)
          Positioned.fill(
            child: SafeArea(
              child: BistPanel(onClose: () => setState(() => _open = false), onRun: () => setState(() => _open = false)),
            ),
          )
        else
          Positioned(
            left: pos.dx,
            top: pos.dy,
            child: GestureDetector(
              onPanUpdate: (d) => setState(() => _pos = pos + d.delta),
              child: ListenableBuilder(
                listenable: Bist.instance,
                // While running the button lets touches through, so it never covers what the script taps
                builder: (context, _) => IgnorePointer(
                  ignoring: Bist.instance.isRunning,
                  child: FloatingActionButton.small(
                    heroTag: null,
                    tooltip: 'BIST',
                    backgroundColor: Bist.instance.isRunning ? Colors.blue : Colors.black87,
                    foregroundColor: Colors.white,
                    onPressed: () => setState(() => _open = true),
                    child: Bist.instance.isRunning
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('BIST', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
