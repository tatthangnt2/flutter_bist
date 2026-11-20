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
    Bist.instance.add(BistSuite.decode(File('assets/bist/demo.json').readAsStringSync()));
    await tester.pumpWidget(const DemoApp());

    BistResult? result;
    Bist.instance.run(Bist.instance.find('demo')!).then((r) => result = r).ignore();
    final until = DateTime.now().add(const Duration(seconds: 60));
    while (result == null && DateTime.now().isBefore(until)) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final failed = result!.cases.where((u) => u.status.isFailure).map((u) => '${u.number} ${u.unit.name}: ${u.error} (${u.dir})');
    expect(result!.status, BistStatus.passed, reason: failed.join('\n'));
    expect(result!.cases.length, 4);
  });
}
