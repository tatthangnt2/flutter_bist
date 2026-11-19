import 'dart:io';

import 'package:flutter_bist/flutter_bist.dart' hide expect;
import 'package:flutter_bist_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs assets/bist/demo.json against the demo app with the default BistProvider
void main() {
  testWidgets('demo script passes', (tester) async {
    Bist.init();
    Bist.instance.screenshots = false;
    BistTouch.wait = (d) => Future<void>.delayed(d);
    Bist.instance.add(TestGroup.decode(File('assets/bist/demo.json').readAsStringSync()));
    await tester.pumpWidget(const DemoApp());

    BistResult? report;
    Bist.instance.run(Bist.instance.find('demo')!).then((r) => report = r).ignore();
    final until = DateTime.now().add(const Duration(seconds: 60));
    while (report == null && DateTime.now().isBefore(until)) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final failed = report!.units.expand((u) => u.steps).where((s) => !s.ok).map((s) => '${s.label} ${s.cmd}: ${s.error}');
    expect(report!.status, BistStatus.passed, reason: failed.join('\n'));
    expect(report!.units.length, 4);
  });
}
