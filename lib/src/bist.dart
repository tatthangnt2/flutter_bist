part of '../flutter_bist.dart';

/// Loads and runs BIST scripts. Use the single instance: `Bist.instance` (static helpers forward to it).
///
/// Scripts (JSON of `package:flutter_bist/model.dart`, the root is a `TestGroup`) are added with [add] / [loadAssets]; [run]
/// runs a node and its preconditions, results go to [reports]. Agents can run scripts without tapping:
/// `--dart-define=BIST_RUN_IDS=<id or number>[,...]` (debug / profile builds). Every action also prints a `BIST|{...}` line.
class Bist extends ChangeNotifier {
  Bist._();

  /// The single instance
  static final instance = Bist._();

  /// Tracks routes for the default [BistProvider] – add it to `MaterialApp.navigatorObservers`
  static final navigatorObserver = BistNavigatorObserver();

  /// Ids / numbers to run when the app starts (`--dart-define=BIST_RUN_IDS=...`), debug / profile builds only
  // ignore: constant_identifier_names – same name as the --dart-define key
  static const BIST_RUN_IDS = String.fromEnvironment('BIST_RUN_IDS');

  /// Connects BIST to the app; replace it with [init]
  BistProvider provider = BistProvider();

  /// Connects BIST to the app and loads its scripts:
  ///
  /// - [provider]: how BIST talks to the app (default: plain Flutter app).
  /// - [scriptAssets]: asset path prefix of the scripts, e.g. `'assets/bist/'` – loads every `*.bist` / `*.json` there
  ///   ([loadAssets]); `null` loads nothing (add scripts later with [add] / [loadAssets]).
  /// - [dartDefine]: run the scripts named by `--dart-define=BIST_RUN_IDS=<id or number>[,...]` once the app is ready
  ///   ([runFromEnvironment], in the background; debug / profile builds only, nothing happens without `BIST_RUN_IDS`).
  ///
  /// Completes when the scripts are loaded (not when the auto-run ends), with the number of script files loaded:
  /// ```dart
  /// await Bist.init(scriptAssets: 'assets/bist/');
  /// runApp(const MyApp());
  /// ```
  ///
  /// [bundle] replaces `rootBundle` (tests).
  static Future<int> init({BistProvider? provider, String? scriptAssets, bool dartDefine = true, AssetBundle? bundle}) async {
    instance.provider = provider ?? BistProvider();
    final count = scriptAssets == null ? 0 : await instance.loadAssets(scriptAssets, bundle: bundle);
    if (dartDefine) unawaited(instance.runFromEnvironment());
    return count;
  }

  final _scripts = <TestGroup>[];
  final _reports = <BistReport>[];
  final _lastStatus = Expando<BistStatus>('bistStatus');
  _BistRun? _current;

  /// Values the app declares for `getEnv` / `{{env:<key>}}`, e.g. `Bist.instance.values['user.code'] = () => user.code;`
  /// (checked before [BistProvider.env]). Never declare tokens or passwords.
  final values = <String, String? Function()>{};

  /// Take a screenshot when a step fails / has `shot` (turn off in widget tests: screenshots need real time)
  bool screenshots = true;

  /// Skip the tests that need a tester ([TestUnit.needsTester]: `confirm` / `ask`) – reported as skipped, not run
  bool skipTester = false;

  /// Test running now – logs / errors at this moment belong to it
  final currentUnit = ValueNotifier<TestUnit?>(null);

  /// Roots of the loaded scripts (one per script file)
  List<TestGroup> get scripts => List.unmodifiable(_scripts);

  /// Runs, newest first
  List<BistReport> get reports => List.unmodifiable(_reports);

  bool get isRunning => _current != null;

  void _changed() => notifyListeners();

  /// Adds a script tree (replaces the one with the same root id)
  void add(TestGroup root) {
    final i = _scripts.indexWhere((e) => e.id == root.id);
    if (i >= 0) {
      _scripts[i] = root;
    } else {
      _scripts.add(root);
    }
    notifyListeners();
  }

  /// Removes every script
  void clear() {
    _scripts.clear();
    notifyListeners();
  }

  /// Removes every report
  void clearReports() {
    _reports.clear();
    notifyListeners();
  }

  /// Loads every `*.bist` / `*.json` asset whose path starts with [prefix] (e.g. `assets/bist/`), sorted by name. Invalid files
  /// are skipped (printed to the console). Returns the number of files loaded.
  Future<int> loadAssets(String prefix, {AssetBundle? bundle}) async {
    final b = bundle ?? rootBundle;
    var count = 0;
    final manifest = await AssetManifest.loadFromAssetBundle(b);
    final keys = manifest.listAssets().where((k) => k.startsWith(prefix) && (k.endsWith('.bist') || k.endsWith('.json'))).toList()..sort();
    for (final key in keys) {
      try {
        add(TestGroup.decode(await b.loadString(key)));
        count++;
      } catch (e) {
        debugPrint('[BIST] Skipped $key: $e');
      }
    }
    return count;
  }

  /// Node with [idOrNumber] (an id, or a number like `2.1.3` – numbers of the n-th root start with n)
  TestCase? find(String idOrNumber) {
    for (final g in _scripts) {
      final rs = g.findId(idOrNumber);
      if (rs != null) return rs;
    }
    final parts = idOrNumber.split('.');
    final i = int.tryParse(parts.first);
    if (i == null || i < 1 || i > _scripts.length) return null;
    final root = _scripts[i - 1];
    return parts.length == 1 ? root : root.findNumber(parts.skip(1).join('.'));
  }

  /// Number of [c] in the list of scripts (the n-th root → `n`, children → `n.1.2`)
  String numberOf(TestCase c) {
    final root = c.path.first;
    final i = _scripts.indexOf(root as TestGroup) + 1;
    return c.number.isEmpty ? '$i' : '$i.${c.number}';
  }

  /// Status of the last run of [c] (a test, or a group: failed if a child failed)
  BistStatus lastStatus(TestCase c) {
    if (c is TestUnit) return _lastStatus[c] ?? BistStatus.none;
    final all = (c as TestGroup).units.map(lastStatus).toList();
    if (all.any((e) => e == BistStatus.running)) return BistStatus.running;
    if (all.any((e) => e.isFailure)) return BistStatus.failed;
    if (all.isNotEmpty && all.every((e) => e == BistStatus.passed || e == BistStatus.manual || e == BistStatus.notApplicable)) {
      return all.any((e) => e == BistStatus.passed) ? BistStatus.passed : all.first;
    }
    return BistStatus.none;
  }

  /// App version for `minVersion` / `maxVersion` (`null` = unknown, every script applies)
  TestVersion? get appVersion {
    final v = provider.appVersion;
    if (v == null) return null;
    try {
      return TestVersion.parse(v);
    } on FormatException {
      return TestVersion.tryFrom(v);
    }
  }

  bool _runFromEnvironmentStarted = false;

  /// Runs [BIST_RUN_IDS] (debug / profile builds) once the app shows its first screen. Only the first call does anything
  /// ([init] already calls it unless `dartDefine: false`), so older code that also calls it does not run scripts twice.
  Future<void> runFromEnvironment({Duration delay = const Duration(seconds: 3)}) async {
    if (kReleaseMode || BIST_RUN_IDS.isEmpty || _runFromEnvironmentStarted) return;
    _runFromEnvironmentStarted = true;
    final until = DateTime.now().add(const Duration(minutes: 2));
    while (!provider.isReady && DateTime.now().isBefore(until)) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    await Future<void>.delayed(delay);
    for (final id in BIST_RUN_IDS.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty)) {
      final c = find(id);
      if (c == null) {
        _print({'run': id, 'ok': false, 'error': 'No such node: $id'});
        continue;
      }
      await run(c);
    }
  }

  /// Runs [c]: preconditions of its parent groups, the nodes before it inside a `TestSequence`, then [c]
  Future<BistReport> run(TestCase c) async {
    final report = BistReport(c, numberOf(c));
    if (_current != null) {
      report.done = true;
      _print({'run': report.number, 'ok': false, 'error': 'Another run is in progress'});
      return report;
    }
    _reports.insert(0, report);
    final r = _current = _BistRun(this, report);
    notifyListeners();
    try {
      await r._exec(c.path.first, c);
    } finally {
      r.close();
      _current = null;
      currentUnit.value = null;
    }
    report
      ..done = true
      ..duration = DateTime.now().difference(report.time)
      ..changed();
    _print({
      'run': report.number,
      'name': c.name,
      'done': true,
      'status': report.status.name,
      for (final s in BistStatus.values)
        if (report.count(s) > 0) s.name: report.count(s),
      'ms': report.duration.inMilliseconds,
      if (r.unusedFiles > 0) 'warn': '${r.unusedFiles} pickFile file(s) never used (no file picker opened after them)',
    });
    notifyListeners();
    return report;
  }

  static void _print(Map<String, Object?> line) {
    // ignore: avoid_print
    print('$kBistLogPrefix${jsonEncode(line)}');
  }
}
