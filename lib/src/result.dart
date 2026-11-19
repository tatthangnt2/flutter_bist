part of '../flutter_bist.dart';

/// Prefix of every result line in the console – agents read them with `adb logcat -d | grep "BIST|"` or `flutter run` output
const kBistLogPrefix = 'BIST|';

/// Version of the flutter_bist package (same as `version:` in its pubspec.yaml – a test checks it)
const kBistVersion = '0.1.0';

/// Status of a test in a report
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

/// Result of one action
class BistStepResult {
  /// `pre`, `step`, `after`
  final String phase;
  final String label;
  final String cmd;
  final bool ok;
  final int ms;
  final String? error;

  /// Screenshot file path (failed steps and steps with `shot`)
  final String? shot;

  /// Texts on screen when the step failed (so you know what the screen showed without the screenshot)
  final List<String> screen;

  /// Tags of app error logs written during the step
  final List<String> appErrors;

  const BistStepResult({
    required this.phase,
    required this.label,
    required this.cmd,
    required this.ok,
    required this.ms,
    this.error,
    this.shot,
    this.screen = const [],
    this.appErrors = const [],
  });
}

/// Result of one [TestUnit] in a run
class BistUnitResult extends ChangeNotifier {
  final TestUnit unit;
  final String number;
  final steps = <BistStepResult>[];
  BistStatus _status;
  String? error;
  Duration duration = Duration.zero;

  BistUnitResult(this.unit, this.number, [this._status = BistStatus.none]);

  BistStatus get status => _status;

  set status(BistStatus v) {
    _status = v;
    notifyListeners();
  }
}

/// One run (▶ on a node / `BIST_RUN_IDS`)
class BistResult extends ChangeNotifier {
  final TestCase target;
  final String number;
  final DateTime time = DateTime.now();
  final units = <BistUnitResult>[];
  bool done = false;
  Duration duration = Duration.zero;

  BistResult(this.target, this.number);

  int count(BistStatus s) => units.where((e) => e.status == s).length;

  /// Share of the tests of [target] that have finished, 0..1 (1 once the run is done) – the progress ring of the BIST button
  double get progress {
    if (done) return 1;
    final c = target;
    final all = c is TestGroup ? c.units : [if (c is TestUnit) c];
    if (all.isEmpty) return 0;
    final finished = all.where((u) => units.any((r) => identical(r.unit, u) && r.status != BistStatus.running)).length;
    return finished / all.length;
  }

  BistStatus get status {
    if (!done) return BistStatus.running;
    if (units.any((e) => e.status.isFailure)) return units.any((e) => e.status == BistStatus.failed) ? BistStatus.failed : BistStatus.preFailed;
    if (units.isNotEmpty && units.every((e) => e.status == BistStatus.manual)) return BistStatus.manual;
    if (units.isNotEmpty && units.every((e) => e.status == BistStatus.notApplicable)) return BistStatus.notApplicable;
    return BistStatus.passed;
  }

  void changed() => notifyListeners();
}
