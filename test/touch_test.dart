import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bist/flutter_bist.dart';
import 'package:flutter_test/flutter_test.dart';

/// BistTouch: real pointer events and keyboard input on the running app
void main() {
  Future<void> setUpScreen(WidgetTester tester, Widget body) async {
    BistTouch.wait = (d) => tester.pump(d);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));
  }

  group('Tap', () {
    testWidgets('tapping the text of a button presses it', (tester) async {
      var taps = 0;
      await setUpScreen(
        tester,
        Center(
          child: ElevatedButton(onPressed: () => taps++, child: const Text('Send')),
        ),
      );
      expect(await BistTouch.tap(tester.element(find.text('Send'))), isNull);
      expect(taps, 1);
    });

    testWidgets('a covered button: error, not pressed', (tester) async {
      var taps = 0;
      await setUpScreen(
        tester,
        Stack(
          children: [
            Center(
              child: ElevatedButton(onPressed: () => taps++, child: const Text('Send')),
            ),
            const Positioned.fill(child: ColoredBox(color: Colors.black54)),
          ],
        ),
      );
      expect(await BistTouch.tap(tester.element(find.text('Send'))), contains('Covered'));
      expect(taps, 0);
    });

    testWidgets('long press calls onLongPress, not onTap', (tester) async {
      var taps = 0, longs = 0;
      await setUpScreen(
        tester,
        Center(
          child: GestureDetector(onTap: () => taps++, onLongPress: () => longs++, child: const Text('Message')),
        ),
      );
      expect(await BistTouch.longPress(tester.element(find.text('Message'))), isNull);
      expect((taps, longs), (0, 1));
    });
  });

  group('Type', () {
    testWidgets('runs onChanged and the input formatters', (tester) async {
      String? changed;
      await setUpScreen(
        tester,
        Center(
          child: TextField(
            decoration: const InputDecoration(labelText: 'Phone'),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
            onChanged: (v) => changed = v,
          ),
        ),
      );
      expect(await BistTouch.enterText(tester.element(find.byType(TextField)), '09a12'), isNull);
      expect(changed, '0912');
    });

    testWidgets('append adds after the current text', (tester) async {
      final c = TextEditingController(text: 'Hi');
      await setUpScreen(tester, Center(child: TextField(controller: c)));
      expect(await BistTouch.enterText(tester.element(find.byType(TextField)), ' there', append: true), isNull);
      expect(c.text, 'Hi there');
    });

    testWidgets('read-only input: error, text unchanged', (tester) async {
      final c = TextEditingController(text: 'old');
      await setUpScreen(tester, Center(child: TextField(controller: c, readOnly: true)));
      expect(await BistTouch.enterText(tester.element(find.byType(TextField)), 'new'), contains('Read only'));
      expect(c.text, 'old');
    });
  });

  group('Scroll', () {
    Widget list(ScrollController c) => ListView.builder(
      controller: c,
      itemCount: 100,
      itemBuilder: (_, i) => SizedBox(height: 50, child: Text('Item $i')),
    );

    testWidgets('swipe scrolls the list', (tester) async {
      final c = ScrollController();
      await setUpScreen(tester, list(c));
      expect(await BistTouch.scroll(tester.element(find.byType(Scrollable)), distance: 300), isNull);
      expect(c.offset, greaterThan(250));
    });

    testWidgets('fling: false moves exactly the dragged distance', (tester) async {
      final c = ScrollController();
      await setUpScreen(tester, list(c));
      expect(await BistTouch.scroll(tester.element(find.byType(Scrollable)), distance: 300, fling: false), isNull);
      expect(c.offset, closeTo(300, 30));
    });
  });
}
