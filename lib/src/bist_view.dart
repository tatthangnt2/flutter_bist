/// Ready-made UI for BIST: [BistView] (scripts + reports) and [BistView.overlay] (the app plus a floating "BIST" button that
/// opens [BistView] in a dialog). [BistView.units] / [BistView.reports] are the two sections, for embedding in your own
/// debug screen. Plain Material, works in any app; texts come from [BistLocalizations] (English by default).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../flutter_bist.dart';

export 'localizations.dart';
export 'logo.dart' show BistLogo, BistIcon;

const _rowText = TextStyle(fontSize: 13, color: Color(0xFF222222));
const _subText = TextStyle(fontSize: 11, color: Color(0xFF777777));

/// Scripts (Test units) and run reports (Test reports) of [Bist.instance]:
///
/// - Test units: the script tree (name, tags). Tap a group to open / close it, **long-press** a node for the run dialog
///   (what it is, "Screenshot on failure", Run); ▶ in the header runs everything.
/// - Test reports: one row per run (time · duration · counts, red when something failed); open it for the tree of what
///   ran – "name ✓ 1.2s" for passed tests, the error in red under failed ones, tap a test for its steps.
///
/// Scrollable; use [units] / [reports] to put the sections into your own list.
class BistView extends StatelessWidget {
  /// Called before a run starts (e.g. close / minimize this view so the app screen is visible)
  final VoidCallback? onRun;

  /// Shown as a close button in the header
  final VoidCallback? onClose;

  /// Texts (English by default)
  /// Texts; `null` = [BistLocalizations.of] (from [BistLocalizationsDelegate], English when the app has none)
  final BistLocalizations? localizations;

  const BistView({super.key, this.onRun, this.onClose, this.localizations});

  /// Test units section (not scrollable)
  static Widget units({VoidCallback? onRun, BistLocalizations? localizations}) => _UnitsSection(onRun: onRun, localizations: localizations);

  /// Test reports section (not scrollable)
  static Widget reports({BistLocalizations? localizations}) => _ReportsSection(localizations: localizations);

  /// For `MaterialApp.builder`: the app plus a small draggable "BIST" button; tapping it opens [BistView] in a dialog,
  /// running a script closes the dialog. Shown when [enabled] (default: debug / profile builds).
  static Widget overlay(BuildContext context, Widget? child, {bool? enabled, BistLocalizations? localizations}) =>
      _BistOverlay(enabled: enabled ?? !const bool.fromEnvironment('dart.vm.product'), text: localizations, child: child);

  @override
  Widget build(BuildContext context) {
    final text = localizations ?? BistLocalizations.of(context);
    return Material(
      color: Colors.white,
      child: Column(
        children: [
          _Header(text: text, onClose: onClose),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                _DataSection(text: text),
                const Divider(height: 1),
                units(onRun: onRun, localizations: text),
                const Divider(height: 1),
                reports(localizations: text),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Header of [BistView]: BIST logo with the library version, the app (name, version, build mode) and device, close button
class _Header extends StatelessWidget {
  final BistLocalizations text;
  final VoidCallback? onClose;

  const _Header({required this.text, required this.onClose});

  static String get _mode => kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug');

  static String _os() {
    if (kIsWeb) return 'Web';
    final name = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Android',
      TargetPlatform.iOS => 'iOS',
      TargetPlatform.macOS => 'macOS',
      TargetPlatform.windows => 'Windows',
      TargetPlatform.linux => 'Linux',
      TargetPlatform.fuchsia => 'Fuchsia',
    };
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final p = Bist.instance.provider;
    final app = [?p.appName, if (p.appVersion != null) 'v${p.appVersion}', '($_mode)'].join(' ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Row(
        children: [
          // Logo with the library version inside the same dark frame
          Container(
            padding: const EdgeInsets.only(bottom: 3),
            decoration: BoxDecoration(color: const Color(0xFF202124), borderRadius: BorderRadius.circular(5)),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BistLogo(height: 26),
                Text('v$kBistVersion', style: TextStyle(fontSize: 9, height: 1.1, color: Color(0xFFBDBDBD))),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _rowText.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                // Like the TLT panel title: device · server
                Text([p.deviceName ?? _os(), ?p.serverName].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: _subText.copyWith(fontSize: 12)),
              ],
            ),
          ),
          if (onClose != null) IconButton(tooltip: text.close, icon: const Icon(Icons.close), onPressed: onClose),
        ],
      ),
    );
  }
}

/// Test data: data and files that come with the scripts (coming soon)
class _DataSection extends StatelessWidget {
  final BistLocalizations text;

  const _DataSection({required this.text});

  @override
  Widget build(BuildContext context) => _Section(
    title: text.data,
    count: 0,
    initiallyOpen: false,
    builder: (_) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 16, 8),
      child: Text(text.noData, style: _subText),
    ),
  );
}

/// Section header like an ExpansionTile: "Title (n)", optional actions, then the expand arrow on the right
class _Section extends StatefulWidget {
  final String title;
  final int count;
  final List<Widget> actions;
  final WidgetBuilder builder;

  final bool initiallyOpen;

  const _Section({required this.title, required this.count, required this.builder, this.actions = const [], this.initiallyOpen = true});

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: widget.title,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF222222)),
                        ),
                        TextSpan(
                          text: ' (${widget.count})',
                          style: const TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
                ...widget.actions,
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: _open ? .5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more, size: 24, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
        if (_open) widget.builder(context),
      ],
    );
  }
}

class _UnitsSection extends StatelessWidget {
  final VoidCallback? onRun;
  final BistLocalizations? localizations;

  const _UnitsSection({required this.onRun, required this.localizations});

  Future<void> _runAll(List<TestGroup> roots) async {
    onRun?.call();
    for (final r in roots) {
      await Bist.instance.run(r);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = localizations ?? BistLocalizations.of(context);
    final bist = Bist.instance;
    return ListenableBuilder(
      listenable: bist,
      builder: (context, _) {
        final roots = bist.scripts;
        return _Section(
          title: text.units,
          count: roots.length,
          actions: [
            IconButton(
              tooltip: text.runAll,
              visualDensity: VisualDensity.compact,
              onPressed: bist.isRunning || roots.isEmpty ? null : () => _runAll(roots),
              icon: Icon(Icons.play_arrow_rounded, color: bist.isRunning ? Colors.grey : Colors.green, size: 24),
            ),
          ],
          builder: (_) => roots.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 16, 8),
                  child: Text(text.noScripts, style: _subText),
                )
              : Padding(
                  padding: const EdgeInsets.only(left: 8, right: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [for (final r in roots) _CaseRow(c: r, level: 0, onRun: onRun, text: text)],
                  ),
                ),
        );
      },
    );
  }
}

class _CaseRow extends StatefulWidget {
  final TestCase c;
  final int level;
  final VoidCallback? onRun;
  final BistLocalizations text;

  const _CaseRow({required this.c, required this.level, required this.onRun, required this.text});

  @override
  State<_CaseRow> createState() => _CaseRowState();
}

class _CaseRowState extends State<_CaseRow> {
  late bool _expanded = widget.level == 0;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final text = widget.text;
    final bist = Bist.instance;
    final version = bist.appVersion;
    final applies = version == null || c.appliesTo(version);
    final group = c is TestGroup ? c : null;
    final tags = [if (c is TestSequence) text.sequential, if (c.writes) text.writes, if (c.manual != null) text.needsTester, if (!applies) text.notApplicable];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: group == null ? null : () => setState(() => _expanded = !_expanded),
          onLongPress: () => _RunDialog.show(context, c, onRun: widget.onRun, text: text),
          child: Padding(
            padding: EdgeInsets.only(left: 12.0 * widget.level, top: 6, bottom: 6, right: 8),
            child: Row(
              children: [
                SizedBox(
                  width: _Fold.chevron,
                  child: group == null ? null : Icon(_expanded ? Icons.expand_more : Icons.chevron_right, size: 18, color: Colors.grey),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${bist.numberOf(c)}. ${c.name}',
                          style: _rowText.copyWith(color: applies ? null : Colors.grey),
                        ),
                        if (tags.isNotEmpty) TextSpan(text: '  ${tags.join(' · ')}', style: _subText),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (group != null && _expanded)
          for (final child in group.cases) _CaseRow(c: child, level: widget.level + 1, onRun: widget.onRun, text: text),
      ],
    );
  }
}

class _ReportsSection extends StatelessWidget {
  final BistLocalizations? localizations;

  const _ReportsSection({required this.localizations});

  @override
  Widget build(BuildContext context) {
    final text = localizations ?? BistLocalizations.of(context);
    final bist = Bist.instance;
    return ListenableBuilder(
      listenable: bist,
      builder: (context, _) => _Section(
        title: text.reports,
        count: bist.reports.length,
        builder: (_) => bist.reports.isEmpty
            ? Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 16, 8),
                child: Text(text.noReports, style: _subText),
              )
            : Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (final r in bist.reports) _ReportTile(report: r, text: text)],
                ),
              ),
      ),
    );
  }
}

/// One run: name; second line "status icon time · duration · counts" (red when a test failed); opens to the tree of the
/// node that was run.
class _ReportTile extends StatelessWidget {
  final BistResult report;
  final BistLocalizations text;

  const _ReportTile({required this.report, required this.text});

  String _time(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    final now = DateTime.now();
    final day = t.year == now.year && t.month == now.month && t.day == now.day ? text.today : '${two(t.day)}/${two(t.month)}/${t.year}';
    return '$day, ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: report,
      builder: (context, _) {
        final counts = [
          for (final x in BistStatus.values)
            if (x != BistStatus.running && report.count(x) > 0) '${text.status(x)} ${report.count(x)}',
        ].join(' · ');
        final line = [_time(report.time), report.done ? _duration(report.duration) : text.inProgress, if (counts.isNotEmpty) counts].join(' · ');
        final failed = report.units.any((u) => u.status.isFailure);
        return _Fold(
          padding: const EdgeInsets.only(left: 4, right: 8, top: 4, bottom: 4),
          initiallyOpen: !report.done,
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${report.number}. ${report.target.name}',
                style: _rowText.copyWith(fontWeight: failed ? FontWeight.w600 : null, color: failed ? Colors.red : null),
              ),
              _statusLine(report.status, line, failed ? _subText.copyWith(color: Colors.red) : _subText),
            ],
          ),
          children: [..._ReportTree(report, text).nodes(report.target, 1), const SizedBox(height: 6)],
        );
      },
    );
  }
}

/// `0.4s`, `12s`, `1m 05s`
String _duration(Duration d) {
  final ms = d.inMilliseconds;
  if (ms < 10000) return '${(ms / 1000).toStringAsFixed(1)}s';
  if (ms < 60000) return '${(ms / 1000).round()}s';
  return '${d.inMinutes}m ${(d.inSeconds % 60).toString().padLeft(2, '0')}s';
}

/// Result tree of one run, shaped like the script (the root is the node that was run)
class _ReportTree {
  final BistResult report;
  final BistLocalizations text;

  _ReportTree(this.report, this.text);

  BistUnitResult? resultOf(TestUnit u) => report.units.where((r) => identical(r.unit, u)).lastOrNull;

  /// [c] is the node that was run: its children (its name is already in the header), or itself for a test
  List<Widget> nodes(TestCase c, int level) {
    if (c is TestUnit) return [_unit(c, level)];
    return [for (final x in (c as TestGroup).cases) ..._node(x, level)];
  }

  List<Widget> _node(TestCase c, int level) {
    if (c is! TestGroup) return [_unit(c as TestUnit, level)];
    final hasError = c.units.any((u) => resultOf(u)?.status.isFailure ?? false);
    return [
      _Fold(
        padding: EdgeInsets.only(left: 4 + 14.0 * level, right: 8, top: 3, bottom: 3),
        initiallyOpen: true,
        header: Text(
          '${Bist.instance.numberOf(c)}. ${c.name}',
          style: _rowText.copyWith(fontWeight: hasError ? FontWeight.w600 : null, color: hasError ? Colors.red : null),
        ),
        children: [for (final x in c.cases) ..._node(x, level + 1)],
      ),
    ];
  }

  Widget _unit(TestUnit u, int level) {
    final r = resultOf(u);
    final pad = EdgeInsets.only(left: 4 + 14.0 * level, right: 8);
    if (r == null) {
      return Padding(
        padding: pad.add(const EdgeInsets.only(left: _Fold.chevron, top: 3, bottom: 3)),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${Bist.instance.numberOf(u)}. ${u.name}',
                style: _rowText.copyWith(color: Colors.grey),
              ),
              TextSpan(text: '  · ${report.done ? text.notReached : text.waiting}', style: _subText),
            ],
          ),
        ),
      );
    }
    return _UnitTile(result: r, padding: pad, text: text);
  }
}

/// A test in the result tree: "name ✓ 1.2s"; running / failed / needs a tester get a second line. Tap for its steps.
class _UnitTile extends StatelessWidget {
  final BistUnitResult result;
  final EdgeInsets padding;
  final BistLocalizations text;

  const _UnitTile({required this.result, required this.padding, required this.text});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: result,
      builder: (context, _) {
        final r = result;
        final s = r.status;
        final done = s != BistStatus.running;
        final sub = switch (s) {
          BistStatus.running => _statusLine(s, text.runningUnit, _subText),
          _ when s.isFailure => _statusLine(s, r.error ?? text.status(s), _subText.copyWith(color: Colors.red)),
          BistStatus.manual || BistStatus.skipped || BistStatus.notApplicable => _statusLine(s, r.error ?? text.status(s), _subText),
          _ => null,
        };
        return _Fold(
          padding: padding.add(const EdgeInsets.symmetric(vertical: 3)),
          canExpand: r.steps.isNotEmpty,
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${r.number}. ${r.unit.name}',
                      style: _rowText.copyWith(fontWeight: s.isFailure ? FontWeight.w600 : null, color: s.isFailure ? Colors.red : null),
                    ),
                    if (s == BistStatus.passed)
                      const WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(Icons.check_circle, size: 13, color: Colors.green),
                        ),
                      ),
                    if (done && r.duration > Duration.zero) TextSpan(text: '  ${_duration(r.duration)}', style: _subText),
                  ],
                ),
              ),
              ?sub,
            ],
          ),
          children: [
            for (final st in r.steps)
              Padding(
                padding: padding.add(const EdgeInsets.only(left: _Fold.chevron + 4, bottom: 4)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(st.ok ? Icons.check : Icons.close, size: 12, color: st.ok ? Colors.green : Colors.red),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        [
                          '${st.label}. ${st.cmd}  ${_duration(Duration(milliseconds: st.ms))}',
                          if (st.error != null) '→ ${st.error}',
                          if (st.appErrors.isNotEmpty) '${text.appErrors}: ${st.appErrors.join(', ')}',
                          if (st.screen.isNotEmpty) '${text.screen}: ${st.screen.take(12).join(' | ')}',
                          if (st.shot != null) '${text.shot}: ${st.shot}',
                        ].join('\n'),
                        style: _subText.copyWith(color: st.ok ? null : Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Row that opens / closes: › / ⌄ on the left, nothing on the right; tap the whole row
class _Fold extends StatefulWidget {
  /// Width of the chevron column (rows that can't open keep it, so names line up)
  static const chevron = 18.0;

  final Widget header;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final bool initiallyOpen;
  final bool canExpand;

  const _Fold({required this.header, required this.children, required this.padding, this.initiallyOpen = false, this.canExpand = true});

  @override
  State<_Fold> createState() => _FoldState();
}

class _FoldState extends State<_Fold> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final can = widget.canExpand && widget.children.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: can ? () => setState(() => _open = !_open) : null,
          child: Padding(
            padding: widget.padding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: _Fold.chevron,
                  child: can ? Icon(_open ? Icons.expand_more : Icons.chevron_right, size: 18, color: Colors.grey) : null,
                ),
                Expanded(child: widget.header),
              ],
            ),
          ),
        ),
        if (can && _open) ...widget.children,
      ],
    );
  }
}

/// Run dialog (long-press in Test units): what the node is, run options, Run. Inserted into the nearest [Overlay], so it
/// also works above the app's Navigator (debug panels, [BistView.overlay]).
class _RunDialog extends StatefulWidget {
  final TestCase c;
  final VoidCallback onClose;
  final VoidCallback? onRun;
  final BistLocalizations text;

  const _RunDialog({required this.c, required this.onClose, required this.onRun, required this.text});

  static void show(BuildContext context, TestCase c, {VoidCallback? onRun, required BistLocalizations text}) {
    OverlayEntry? e;
    e = OverlayEntry(
      builder: (_) => _RunDialog(c: c, onClose: () => e?.remove(), onRun: onRun, text: text),
    );
    Overlay.maybeOf(context)?.insert(e);
  }

  @override
  State<_RunDialog> createState() => _RunDialogState();
}

class _RunDialogState extends State<_RunDialog> {
  TestCase get c => widget.c;

  /// Compact checkbox, ~10 dp to its label (CheckboxListTile leaves a wide gap)
  Widget _check(String label, bool value, void Function(bool v) set) => InkWell(
    onTap: () => setState(() => set(!value)),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Checkbox(
            value: value,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            onChanged: (v) => setState(() => set(v ?? false)),
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: _rowText)),
        ],
      ),
    ),
  );

  void _run() {
    widget.onClose();
    widget.onRun?.call();
    Bist.instance.run(c);
  }

  @override
  Widget build(BuildContext context) {
    final bist = Bist.instance;
    final text = widget.text;
    final c = this.c;
    final units = c is TestGroup ? c.units : [c as TestUnit];
    final version = bist.appVersion;
    final tester = units.where((u) => u.needsTester).length;
    final info = [
      switch (c) {
        TestSequence() => text.sequence,
        TestGroup() => text.group,
        _ => text.test,
      },
      if (c.id != null) 'id: ${c.id}',
      if (c.isWrites) text.writesInfo,
      if (c.manual != null) text.needsTesterInfo(c.manual!),
      if (c.minVersion != null || c.maxVersion != null) text.versions(c.minVersion, c.maxVersion),
      if (version != null && !c.appliesTo(version)) text.notForVersion('$version'),
    ];
    return GestureDetector(
      onTap: widget.onClose,
      child: Container(
        color: Colors.black26,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: GestureDetector(
          onTap: () {}, // taps inside the dialog don't close it
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Material(
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${bist.numberOf(c)}. ${c.name}', style: _rowText.copyWith(fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(info.join(' · '), style: _subText),
                    const SizedBox(height: 2),
                    // Statistics: tests in this node, how many need a tester (manual / confirm / ask)
                    Text(text.stats(units.length, tester), style: _subText.copyWith(color: const Color(0xFF444444))),
                    const SizedBox(height: 8),
                    _check(text.screenshotOnFailure, bist.screenshots, (v) => bist.screenshots = v),
                    if (tester > 0) _check(text.skipTester, bist.skipTester, (v) => bist.skipTester = v),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(onPressed: widget.onClose, child: Text(text.cancel)),
                        FilledButton.icon(
                          onPressed: bist.isRunning ? null : _run,
                          icon: const Icon(Icons.play_arrow_rounded, size: 20),
                          label: Text(bist.isRunning ? text.busy : text.run),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Second line with the status icon first: a spinner while running, the icon of [s] otherwise
Widget _statusLine(BistStatus s, String text, TextStyle style) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Padding(
      padding: const EdgeInsets.only(top: 1, right: 4),
      child: s == BistStatus.running
          ? const SizedBox.square(dimension: 12, child: CircularProgressIndicator(strokeWidth: 1.5))
          : Icon(s.icon, color: s.color, size: 13),
    ),
    Expanded(child: Text(text, style: style)),
  ],
);

class _BistOverlay extends StatefulWidget {
  final bool enabled;
  final BistLocalizations? text;
  final Widget? child;

  const _BistOverlay({required this.enabled, required this.text, required this.child});

  @override
  State<_BistOverlay> createState() => _BistOverlayState();
}

class _BistOverlayState extends State<_BistOverlay> {
  bool _open = false;
  Offset? _pos;
  late final _entry = OverlayEntry(builder: (context) => _layer(context, _currentPos(context)));

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
    // MaterialApp.builder sits above the Navigator: give BIST its own Overlay (the run dialog, tooltips need one)
    return Stack(
      children: [
        child,
        Positioned.fill(child: Overlay(initialEntries: [_entry])),
      ],
    );
  }

  Widget _layer(BuildContext context, Offset pos) {
    void close() => setState(() => _open = false);
    final size = MediaQuery.sizeOf(context);
    return Stack(
      children: [
        if (_open) ...[
          Positioned.fill(
            child: GestureDetector(
              onTap: close,
              child: const ColoredBox(color: Colors.black38),
            ),
          ),
          // Dialog: BistView in a card, at most 560 wide and 85 % of the screen high
          Center(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 560, maxHeight: size.height * .85),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: BistView(onClose: close, onRun: close, localizations: widget.text),
                  ),
                ),
              ),
            ),
          ),
        ] else
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
                  child: Tooltip(
                    message: (widget.text ?? BistLocalizations.of(context)).title,
                    child: _ButtonIcon(running: Bist.instance.isRunning, onTap: () => setState(() => _open = true)),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// [BistIcon] for the floating button; a progress ring around it while a script runs
class _ButtonIcon extends StatelessWidget {
  final bool running;
  final VoidCallback onTap;

  const _ButtonIcon({required this.running, required this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 52,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Material(
          type: MaterialType.circle,
          color: Colors.transparent,
          elevation: 4,
          child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: const BistIcon(size: 44)),
        ),
        // Share of the tests already run
        if (running && Bist.instance.reports.isNotEmpty)
          ListenableBuilder(
            listenable: Bist.instance.reports.first,
            builder: (context, _) => SizedBox.square(
              dimension: 52,
              child: CircularProgressIndicator(
                value: Bist.instance.reports.first.progress,
                strokeWidth: 3,
                color: const Color(0xFF2EB84F),
                backgroundColor: const Color(0x332EB84F),
              ),
            ),
          ),
      ],
    ),
  );
}
