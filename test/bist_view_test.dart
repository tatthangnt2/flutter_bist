import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bist/flutter_bist.dart' hide expect;
import 'package:flutter_bist/flutter_bist.dart' as b;
import 'package:flutter_test/flutter_test.dart';

/// BistView: Test units (long-press → run dialog), Test results (result tree), BistView.overlay
void main() {
  var gid = 0;

  setUp(() async {
    await Bist.init(dartDefine: false);
    Bist.instance.clear();
    Bist.instance.clearResults();
    Bist.instance.screenshots = false; // screenshots need real time – they hang in widget tests
    BistTouch.wait = (d) => Future<void>.delayed(d);
  });

  BistSuite script() => BistSuite(
    id: 'ui${gid++}',
    name: 'Login',
    units: [
      BistSuite(
        name: 'Account',
        units: [
          BistCase(name: 'Empty fields', steps: [b.wait(50)]),
          BistCase(
            name: 'Wrong password',
            steps: [b.expect(text: 'Not on screen', timeout: 200)],
          ),
        ],
      ),
      BistCase(name: 'Fingerprint', manual: 'Face ID'),
    ],
  );

  Future<void> waitDone(WidgetTester tester) async {
    final until = DateTime.now().add(const Duration(seconds: 20));
    while (Bist.instance.results.isEmpty || !Bist.instance.results.first.done) {
      if (DateTime.now().isAfter(until)) fail('the run did not finish');
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('long-press opens the run dialog; Run calls onRun and adds a run with its result tree', (tester) async {
    Bist.instance.add(script());
    var runs = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BistView(onRun: () => runs++)),
      ),
    );
    expect(find.textContaining('Test units ('), findsOneWidget);

    await tester.longPress(find.text('1. Login'));
    await tester.pumpAndSettle();
    expect(find.text('Screenshot on failure'), findsOneWidget);
    expect(find.textContaining('3 tests'), findsOneWidget);

    await tester.tap(find.text('Run'));
    await waitDone(tester);
    expect(runs, 1);
    expect(Bist.instance.results, hasLength(1));

    final error = tester.widget<Text>(find.textContaining('Not found: text "Not on screen"'));
    expect(error.style?.color, Colors.red);
    expect(find.byIcon(Icons.check_circle), findsOneWidget); // 1.1.1 passed
    expect(find.text('Face ID'), findsOneWidget); // needs a tester
    expect(tester.widget<Text>(find.text('1. Login').last).style?.color, Colors.red); // result header
    expect(tester.widget<Text>(find.text('1.1. Account').last).style?.color, Colors.red); // group with a failed test
  });

  testWidgets('BistView.overlay: the BIST button opens BistView in a dialog, × closes it', (tester) async {
    Bist.instance.add(script());
    await tester.pumpWidget(
      MaterialApp(
        builder: (c, child) => BistView.overlay(c, child, enabled: true),
        home: const Scaffold(body: Text('App')),
      ),
    );
    expect(find.textContaining('Test units ('), findsNothing);
    await tester.tap(find.byType(BistIcon));
    await tester.pumpAndSettle();
    expect(find.textContaining('Test units ('), findsOneWidget);
    expect(find.text('1. Login'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Test units ('), findsNothing);
    expect(find.text('App'), findsOneWidget);
  });

  testWidgets('texts come from BistLocalizations', (tester) async {
    Bist.instance.add(script());
    const text = BistLocalizations(units: 'Kịch bản', results: 'Kết quả', noResults: 'Chưa chạy');
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: BistView(localizations: text)),
      ),
    );
    expect(find.textContaining('Kịch bản ('), findsOneWidget);
    expect(find.textContaining('Kết quả ('), findsOneWidget);
    expect(find.text('Chưa chạy'), findsOneWidget);
  });

  testWidgets('BistLocalizationsDelegate: texts by the app language, the fallback (English) for other languages', (tester) async {
    Bist.instance.add(script());
    // The test has no flutter_localizations, so the app stays in English: map 'en' to other texts to see the delegate work
    const custom = BistLocalizations(units: 'Kịch bản', results: 'Kết quả', title: 'KIỂM THỬ');
    Future<void> pump(Map<String, BistLocalizations> translations) => tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: [BistLocalizationsDelegate(translations), DefaultMaterialLocalizations.delegate, DefaultWidgetsLocalizations.delegate],
        builder: (c, child) => BistView.overlay(c, child, enabled: true),
        home: const Scaffold(body: BistView()),
      ),
    );
    await pump({'en': custom});
    await tester.pumpAndSettle();
    expect(find.textContaining('Kịch bản ('), findsOneWidget);
    expect(find.byTooltip('KIỂM THỬ'), findsOneWidget); // floating button tooltip (the header shows the logo)

    await pump({'vi': custom}); // no English entry → fallback
    await tester.pumpAndSettle();
    expect(find.textContaining('Test units ('), findsOneWidget);
    expect(find.byTooltip('BIST'), findsOneWidget);
  });

  test('kBistVersion matches pubspec.yaml', () {
    final m = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync());
    expect(kBistVersion, m?.group(1));
  });

  testWidgets('floating button: BistIcon; a progress ring (share of tests run) around it while a script runs', (tester) async {
    Bist.instance.add(script());
    await tester.pumpWidget(
      MaterialApp(
        builder: (c, child) => BistView.overlay(c, child, enabled: true),
        home: const Scaffold(body: Text('App')),
      ),
    );
    expect(find.byType(BistIcon), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    Bist.instance.run(Bist.instance.scripts.first.units.first).ignore(); // group "Account": 2 tests
    await tester.pump(const Duration(milliseconds: 20));
    double? ring() => tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator)).value;
    expect(ring(), 0, reason: 'nothing finished yet');
    final values = <double?>{};
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      if (find.byType(CircularProgressIndicator).evaluate().isNotEmpty) values.add(ring());
    }
    expect(values, contains(0.5), reason: 'one of two tests finished');
    final until = DateTime.now().add(const Duration(seconds: 20));
    while (Bist.instance.isRunning && DateTime.now().isBefore(until)) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
