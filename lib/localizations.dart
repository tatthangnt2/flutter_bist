/// Texts of the BIST UI ([BistLocalizations], English by default) and [BistLocalizationsDelegate] to pick them by the app
/// locale. Exported by `package:flutter_bist/bist_view.dart`.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'flutter_bist.dart';

/// Texts of [BistView]. Translate by creating an instance with your texts, then either add a [BistLocalizationsDelegate] to
/// `MaterialApp.localizationsDelegates` or pass it to [BistView] / [BistView.overlay] (`localizations:`).
class BistLocalizations {
  /// Texts of the nearest [Localizations] (from [BistLocalizationsDelegate]); English when the app has no delegate
  static BistLocalizations of(BuildContext context) => Localizations.of<BistLocalizations>(context, BistLocalizations) ?? const BistLocalizations();

  const BistLocalizations({
    this.title = 'BIST',
    this.units = 'Test units',
    this.reports = 'Test results',
    this.data = 'Test data',
    this.noData = 'Data and files that come with the scripts – coming soon',
    this.noScripts = 'No scripts – Bist.init(scriptAssets: ...) / Bist.instance.add(...)',
    this.noReports = 'No runs yet – long-press a script to run it',
    this.sequential = 'sequential',
    this.writes = '✎ writes data',
    this.needsTester = 'needs a tester',
    this.notApplicable = 'not for this version',
    this.group = 'Group',
    this.sequence = 'Sequential group',
    this.test = 'Test',
    this.tests = _tests,
    this.writesInfo = 'writes data – runs on non-production servers only',
    this.needsTesterInfo = _needsTesterInfo,
    this.versions = _versions,
    this.notForVersion = _notForVersion,
    this.screenshotOnFailure = 'Screenshot on failure',
    this.skipTester = 'Skip tests that need a tester',
    this.stats = _stats,
    this.cancel = 'Cancel',
    this.run = 'Run',
    this.runAll = 'Run all',
    this.busy = 'Another run in progress',
    this.close = 'Close',
    this.today = 'Today',
    this.inProgress = 'running',
    this.runningUnit = 'Running…',
    this.waiting = 'waiting',
    this.notReached = 'not reached',
    this.appErrors = 'App errors',
    this.screen = 'Screen',
    this.shot = 'Screenshot',
    this.status = _status,
  });

  final String title, units, reports, data, noData, noScripts, noReports;

  /// Tags after a script name
  final String sequential, writes, needsTester, notApplicable;

  /// Run dialog
  final String group, sequence, test, writesInfo, screenshotOnFailure, skipTester, cancel, run, runAll, busy, close;

  /// Statistics line of the run dialog: tests in the node, how many need a tester
  final String Function(int total, int tester) stats;
  final String Function(int count) tests;
  final String Function(String reason) needsTesterInfo;
  final String Function(String? min, String? max) versions;
  final String Function(String version) notForVersion;

  /// Reports
  final String today, inProgress, runningUnit, waiting, notReached, appErrors, screen, shot;
  final String Function(BistStatus s) status;

  static String _tests(int n) => n == 1 ? '1 test' : '$n tests';
  static String _stats(int total, int tester) => '${_tests(total)} · $tester need a tester';
  static String _needsTesterInfo(String reason) => 'needs a tester: $reason';
  static String _versions(String? min, String? max) => 'versions ${min ?? ''}..${max ?? ''}';
  static String _notForVersion(String v) => 'not for version $v';
  static String _status(BistStatus s) => s.label;
}

/// Loads [BistLocalizations] for the app locale (by language code); other languages get [fallback] (English by default).
///
/// ```dart
/// MaterialApp(
///   localizationsDelegates: [
///     const BistLocalizationsDelegate({'vi': myVietnameseTexts}),
///     ...GlobalMaterialLocalizations.delegates,
///   ],
///   builder: BistView.overlay,
/// )
/// ```
class BistLocalizationsDelegate extends LocalizationsDelegate<BistLocalizations> {
  /// Texts by language code (`'vi'`, `'fr'`…)
  final Map<String, BistLocalizations> translations;

  /// Texts for languages not in [translations]
  final BistLocalizations fallback;

  const BistLocalizationsDelegate([this.translations = const {}, this.fallback = const BistLocalizations()]);

  /// Every locale is supported: missing languages use [fallback], so BIST never blocks the app's locale
  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<BistLocalizations> load(Locale locale) => SynchronousFuture(translations[locale.languageCode] ?? fallback);

  @override
  bool shouldReload(BistLocalizationsDelegate old) => !identical(old.translations, translations) || !identical(old.fallback, fallback);
}
