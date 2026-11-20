part of '../flutter_bist.dart';

/// Prefix of every result line in the console – agents read them with `adb logcat -d | grep "BIST|"` or `flutter run` output
const kBistLogPrefix = 'BIST|';

/// Version of the flutter_bist package (same as `version:` in its pubspec.yaml – a test checks it)
const kBistVersion = '0.1.0';

/// Status of a test in a run
enum BistStatus {
  none('Not run', Colors.grey),
  running('Running', Colors.blue),
  passed('Passed', Colors.green),
  failed('Failed', Colors.red),
  skipped('Skipped', Colors.grey),
  preFailed('Precondition failed', Colors.orange),
  manual('Needs a tester', Colors.purple),
  notApplicable('Not for this version', Colors.grey);

  final String label;
  final Color color;

  const BistStatus(this.label, this.color);

  bool get isFailure => this == failed || this == preFailed;

  IconData get icon => switch (this) {
    none => Icons.radio_button_unchecked,
    running => Icons.timelapse,
    passed => Icons.check_circle,
    failed => Icons.cancel,
    skipped => Icons.remove_circle_outline,
    preFailed => Icons.warning_amber_rounded,
    manual => Icons.pan_tool_alt_outlined,
    notApplicable => Icons.block,
  };
}

/// Result of one node of the script tree in a run: a test ([unit] is a [BistCase], no [children]) or a suite (results
/// of its children, in script order). A run is the root: the top suite of the node that was run ([target]), with the
/// suites on the way to it, everything inside it (not run yet: [BistStatus.none]) and the tests run before it (earlier
/// items of a `BistSequence`).
///
/// Files: [dir] of the root is the run folder `BistProvider.tempDir()/bist/<yyyy-MM-dd HH-mm-ss>`; [dir] of a test is
/// `<run folder>/<number>` with `pre.log` / `step.log` / `after.log` (one line per action), `error.log` (only the error),
/// `shot_<pre | step | after>_<step>.jpg` (screenshots).
class BistResult extends ChangeNotifier {
  final BistUnit unit;
  final String number;
  final BistResult? parent;
  final children = <BistResult>[];

  /// The node that was run (▶ / `BIST_RUN_IDS`) – set on the root, [unit] elsewhere
  final BistUnit target;

  /// When the result was made (the root: start of the run)
  final DateTime time = DateTime.now();
  BistStatus _status;
  String? error;
  Duration duration = Duration.zero;

  /// Root: run folder; test: its folder (`null` when nothing was written, e.g. a test that did not run)
  String? dir;

  /// The run has ended (root)
  bool done = false;

  BistResult(this.unit, this.number, {this.parent, BistUnit? target, BistStatus status = BistStatus.none}) : target = target ?? unit, _status = status;

  bool get isCase => unit is BistCase;

  BistResult get root => parent?.root ?? this;

  /// Results of every test in this node (itself for a test)
  Iterable<BistResult> get cases sync* {
    if (isCase) yield this;
    for (final c in children) {
      yield* c.cases;
    }
  }

  int count(BistStatus s) => cases.where((e) => e.status == s).length;

  /// Result of [u] inside this node (`null` when not in the tree)
  BistResult? find(BistUnit u) {
    if (identical(unit, u)) return this;
    for (final c in children) {
      final r = c.find(u);
      if (r != null) return r;
    }
    return null;
  }

  /// Share of the tests of [target] that have finished, 0..1 (1 once the run is done) – the progress ring of the BIST button
  double get progress {
    if (root.done) return 1;
    final all = (find(target) ?? this).cases.toList();
    if (all.isEmpty) return 0;
    return all.where((r) => r._status != BistStatus.none && r._status != BistStatus.running).length / all.length;
  }

  /// A test: its own status; a suite: from its tests (failed if one failed); the root: running until the run ends
  BistStatus get status {
    if (parent == null && !done) return BistStatus.running;
    if (isCase) return _status;
    final ran = cases.map((e) => e._status).where((e) => e != BistStatus.none).toList();
    if (ran.isEmpty) return BistStatus.none;
    if (ran.contains(BistStatus.running)) return BistStatus.running;
    if (ran.any((e) => e.isFailure)) return ran.contains(BistStatus.failed) ? BistStatus.failed : BistStatus.preFailed;
    if (ran.every((e) => e == BistStatus.manual)) return BistStatus.manual;
    if (ran.every((e) => e == BistStatus.notApplicable)) return BistStatus.notApplicable;
    return BistStatus.passed;
  }

  set status(BistStatus v) {
    _status = v;
    changed();
  }

  /// Notifies this node and its parents (the run row listens to the root)
  void changed() {
    notifyListeners();
    parent?.changed();
  }

  /// Result of [u] in this run tree (made, with the suites above it, when missing – children kept in script order)
  BistResult node(BistUnit u, String Function(BistUnit) numberOf) {
    var r = root;
    for (final x in u.path.skip(1)) {
      final suite = r.unit as BistSuite;
      var child = r.children.where((c) => identical(c.unit, x)).firstOrNull;
      if (child == null) {
        child = BistResult(x, numberOf(x), parent: r);
        final i = suite.units.indexOf(x);
        final at = r.children.indexWhere((c) => suite.units.indexOf(c.unit) > i);
        r.children.insert(at < 0 ? r.children.length : at, child);
      }
      r = child;
    }
    return r;
  }

  /// Makes the results of every node inside this one (not run yet)
  void fill(String Function(BistUnit) numberOf) {
    final u = unit;
    if (u is! BistSuite) return;
    for (final x in u.units) {
      (children.where((c) => identical(c.unit, x)).firstOrNull ?? node(x, numberOf)).fill(numberOf);
    }
  }
}
