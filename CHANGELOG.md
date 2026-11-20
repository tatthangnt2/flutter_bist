# Changelog

## Unreleased

- `BistLocalizationVi`: Vietnamese texts of the BIST UI (`localizations: const BistLocalizationVi()` or
  `BistLocalizationsDelegate({'vi': BistLocalizationVi()})`), moved from flutter_tlt.
- Files: `lib/src/model.dart` renamed `lib/src/unit.dart` (script tree, validation; `lib/src/action.dart` is its part);
  `TestVersion` moved to `lib/src/bist.dart`. Still all exported by `package:flutter_bist/flutter_bist.dart`.
- Breaking: script classes take the `Bist` prefix – `TestAction` → `BistAction`, `TestUnit` → `BistUnit`, `TestCase` →
  `BistCase`, `TestSuite` → `BistSuite`, `TestSequence` → `BistSequence` (Dart and TypeScript, also the TypeScript node
  types `BistUnitNode` / `BistSuiteNode` / `BistCaseNode`). JSON unchanged (`schema` 4, `"type": "case" | "suite" | "sequence"`).
- Dart: every command is a class extending `BistAction` – `TapBistAction`, `InputBistAction`, `ExpectBistAction`, …
  (`<Command>BistAction`, 30 classes, Dart 3 super parameters: `TapBistAction({super.text, …}) : super('tap')`) –
  and the command name is its constructor tear-off, e.g. `final tap = TapBistAction.new;`. Scripts call `tap(text: 'Send')` as before; the JSON is unchanged. `BistAction.fromJson`
  still returns a plain `BistAction`. `BistAction(cmd, {text, id, …})` is the constructor of the command classes (Dart 3 super parameters, validated); `BistAction.custom(cmd, [json])` builds a raw action (not validated) for custom actions later. Every `BistAction` property is documented. `BistAction` and the command classes live in `lib/src/action.dart` (part of `unit.dart`).
- `WidgetType` adds `checkbox` (also switches), `radio`, `dropdown` (Dart and TypeScript). Breaking:
  `BistProvider.widgetOf(w)` (default: Material / Cupertino widgets; override for your widgets and fall back to
  `super.widgetOf(w)`) replaces `isButton` / `isInput` / `isImage` / `isDropdown`, which now all go through it. `input` also targets a dropdown found by its label.
- Breaking: "report" names follow `BistResult` – `Bist.results` / `clearResults()` (was `reports` / `clearReports()`),
  `BistView.results` (was `BistView.reports`), `BistLocalizations.results` / `noResults` (was `reports` / `noReports`).
- Breaking: one result class – `BistCaseResult` merged into `BistResult`, now a tree shaped like the script: `unit`,
  `number`, `status` (a suite: from its tests), `error`, `duration`, `dir`, `children`, `cases` (every test inside),
  `find(unit)`. A run is the root: the top suite of the node that was run (`target`), with the suites on the way to it,
  the tests run before it (earlier items of a `TestSequence`) and every node inside it (not run yet: `none`); `time`,
  `done`, `progress` on the root. The Test results tree is drawn from it.
- Breaking: `BistStepResult` and `BistCaseResult.steps` removed – a run writes files instead: folder
  `tempDir()/bist/<yyyy-MM-dd HH-mm-ss>/` (root `BistResult.dir`), one folder per test `<number>/` (its `dir`) with
  `pre.log` / `step.log` / `after.log`, `error.log` (only the error) and JPEG screenshots `shot_<phase>_<step>.jpg`
  (new dependency `image`). Tapping a test in Test results shows its folder and logs. `BIST|` lines: no `ms` per step,
  a line per finished test (`case`, `status`, `error`, `dir`), `dir` on the run line. `BistLocalizations`: `folder`
  replaces `appErrors` / `screen` / `shot`.
- Breaking: script tree renamed – `TestUnit` is now the abstract base of every node (was `TestCase`), **`TestCase`** is
  one test with `steps` (was `TestUnit`), **`TestSuite`** is the group (was `TestGroup`; `TestSequence` extends it).
  Children of a suite: `units` (was `cases`); every test inside it: `cases` (was `units`). JSON: `"type": "case" | "suite"
  | "sequence"` (was `unit` / `group`), children key `"units"` (was `"cases"`) – `schema` stays 4. Also `BistCaseResult`
  (was `BistUnitResult`, field `testCase`), `BistResult.cases`, `Bist.currentCase`, `BistLocalizations.suite`; TypeScript
  `TestUnitNode` / `TestCaseNode` / `TestSuiteNode`, `UnitProps`. BIST log: `"case"` key for a test's result.
- Breaking: `BistReport` renamed `BistResult` (one run: target, time, tests, status, progress). Sources: `src/report.dart` →
  `src/result.dart`, `src/runner.dart` → `src/executor.dart` (the runner class is `_BistExecutor`).
- Breaking: `package:flutter_bist/flutter_bist.dart` is the only public library. It now exports everything: the script
  model **and builders** (`tap`, `expect`, `log`…; was `package:flutter_bist/model.dart`), `BistView` / `BistLogo` /
  `BistIcon` (was `bist_view.dart`), `BistLocalizations` (was `localizations.dart`). Test files that also import
  flutter_test: `import 'package:flutter_bist/flutter_bist.dart' hide expect;` (or a prefix). `doc/` renamed `docs/`.
- Run dialog: statistics (tests in the node, how many need a tester) and "Skip tests that need a tester"
  (`Bist.skipTester`; `TestCase.needsTester` = `manual`, or `confirm` / `ask` in its steps / loops / the `pre` / `after`
  of its groups) – skipped tests are reported as Skipped.
- BIST logo: `icon/logo.svg` and the `BistLogo` widget (drawn from the same paths, no font or asset needed); short icon
  `icon/icon.svg` (the B in a circle) and `BistIcon` – the floating button of `BistView.overlay`, with a progress ring
  around it while a script runs (`BistResult.progress`: share of the tests finished).
- `BistView` header: BIST logo with the library version (`kBistVersion`), the app name / version / build mode and the
  device (`BistProvider.appName`, `deviceName`, new – default: the OS name), close button. Sections Test data (data and
  files that come with the scripts – coming soon), Test units, Test results (was Test reports).
- Breaking: `BistPanel` renamed `BistView` and redesigned. Test units: script tree, long-press a node for the run dialog
  (info, "Screenshot on failure", Run), ▶ in the header runs all. Test reports: one row per run (time · duration · counts,
  red on failure), opening to the result tree ("name ✓ 1.2s", errors in red, tap a test for its steps).
  `BistView.overlay` opens it in a dialog; `BistView.units` / `BistView.reports` embed the sections (`package:flutter_bist/bist_view.dart`, was `ui.dart`); texts via
  `BistLocalizations` (English by default; `BistLocalizationsDelegate` picks them by the app locale, or pass
  `localizations:`).
- `Bist.init({provider, scriptAssets, dartDefine = true})` now also loads the scripts under `scriptAssets` and starts the
  `--dart-define=BIST_RUN_IDS=...` auto-run; it returns a `Future<int>` (script files loaded). Replaces
  `Bist.init()` + `loadAssets(...)` + `unawaited(autoRun())`.
- Breaking: `autoRun()` renamed `runFromEnvironment()`, `autoRunIds` renamed `BIST_RUN_IDS` (same name as the define), and the define is now
  `--dart-define=BIST_RUN_IDS=<id or number>[,...]` (was `BIST_RUN`). `runFromEnvironment()` runs only on its first call,
  so calling it again after `init` does not run scripts twice.

## 0.1.0

First release, split out of an in-house Flutter library.

- Script model (`package:flutter_bist/model.dart`, JSON `schema: 4`): `TestGroup` / `TestSequence` / `TestUnit`, 31 commands
  (tap, input, dates, expect / notExpect with input state, count, checked / selected, text match exact / contains / regex,
  swipe, nav, back, runTest, loops, random data, variables from screen / logs / environment, tester dialogs, mockApi /
  offline, pickFile, server).
- Runner `Bist`: real pointer and keyboard input (`BistTouch`), waits, auto-scroll, keyboard handling, reports,
  `BIST|` console lines, screenshots, `--dart-define=BIST_RUN=<id>`, writes refused on production servers.
- `BistProvider`: one class to connect an app or a UI library (screen, navigation, servers, test data, logs, network
  mocking, file picking, custom widgets); defaults work with plain Flutter.
- `BistPanel` / `BistPanel.overlay`: scripts and reports in the app.
- BIST Editor (`bin/editor.html`) and command line (`bin/bist.mjs`), sources in `tools/editor`.
