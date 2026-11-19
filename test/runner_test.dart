import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bist/flutter_bist.dart';
import 'package:flutter_bist/model.dart' as b;
import 'package:flutter_test/flutter_test.dart';

/// Provider of the tests: fake HTTP client, logs, test data, servers, a custom widget
class _TestProvider extends BistProvider {
  bool production = false;
  BistNetworkHook? hook;
  final logs = <void Function(BistLog)>[];
  String? server = 'DEV';

  @override
  bool get isProduction => production;

  @override
  String? get serverName => server;

  @override
  Future<String?> switchServer(String name, Duration timeout) async {
    if (name != 'DEV' && name != 'PROD') return 'Unknown server: $name';
    server = name;
    production = name == 'PROD';
    return null;
  }

  @override
  String? env(String key) => key == 'user.name' ? 'Alice' : null;

  @override
  String? testData(String group, String field) => group == 'Admin' && field == 'userName' ? 'admin01' : null;

  @override
  void Function()? listenLogs(void Function(BistLog log) onLog) {
    logs.add(onLog);
    return () => logs.remove(onLog);
  }

  void log(String tag, {String level = 'info', Object? data}) {
    for (final l in List.of(logs)) {
      l(BistLog(tag, level: level, time: DateTime.now(), data: data));
    }
  }

  @override
  void attachNetwork(BistNetworkHook hook) => this.hook = hook;

  @override
  void detachNetwork() => hook = null;

  @override
  List<String?>? textsOf(Widget w) => w is _IconOnlyButton ? [w.label] : null;

  @override
  bool? isButton(Widget w) => w is _IconOnlyButton ? true : null;
}

final _provider = _TestProvider();

void main() {
  var gid = 0;

  setUp(() {
    Bist.init(provider: _provider);
    _provider.production = false;
    Bist.instance.screenshots = false;
    // The runner waits with plain timers; the pump loop in run() moves time forward (no nested tester.pump)
    BistTouch.wait = (d) => Future<void>.delayed(d);
  });

  Future<void> setUpScreen(WidgetTester tester, Widget body, {TransitionBuilder? builder, Map<String, WidgetBuilder>? routes}) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: builder,
        navigatorObservers: [Bist.navigatorObserver],
        routes: routes ?? const {},
        home: Scaffold(body: body),
      ),
    );
  }

  /// Runs [c] (inside a new root group), pumping frames until it ends
  Future<BistReport> run(WidgetTester tester, TestCase c) async {
    Bist.instance.add(TestGroup(id: 'g${gid++}', name: 'Test group', cases: [c]));
    BistReport? rs;
    Bist.instance.run(c).then((r) => rs = r).ignore();
    // Runner timeouts use real time: pump until done (at most 20 real seconds)
    final until = DateTime.now().add(const Duration(seconds: 20));
    while (rs == null && DateTime.now().isBefore(until)) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(rs, isNotNull, reason: 'the runner did not finish');
    return rs!;
  }

  Future<BistReport> runSteps(WidgetTester tester, List<TestAction> steps, {bool writes = false}) =>
      run(tester, TestUnit(name: 'Test', steps: steps, writes: writes));

  String? firstError(BistReport r) => r.units.expand((u) => u.steps).where((s) => !s.ok).firstOrNull?.error;

  group('Text match', () {
    testWidgets('contains: part of the text', (tester) async {
      await setUpScreen(tester, const Center(child: Text('Saved 3 items')));
      final r = await runSteps(tester, [b.expect(text: 'Saved', match: TextMatch.contains, timeout: 500)]);
      expect(r.status, BistStatus.passed, reason: firstError(r));
    });

    testWidgets('exact (default): part of the text does not match', (tester) async {
      await setUpScreen(tester, const Center(child: Text('Saved 3 items')));
      final r = await runSteps(tester, [b.expect(text: 'Saved', timeout: 300)]);
      expect(r.status, BistStatus.failed);
      expect(firstError(r), contains('Not found'));
    });

    testWidgets('regex', (tester) async {
      await setUpScreen(tester, const Center(child: Text('Total: 1,250.00 USD')));
      final r = await runSteps(tester, [b.expect(text: r'^Total: [\d,.]+ USD$', match: TextMatch.regex, timeout: 500)]);
      expect(r.status, BistStatus.passed, reason: firstError(r));
    });

    testWidgets('input value with match contains', (tester) async {
      final c = TextEditingController(text: 'alice@example.com');
      await setUpScreen(
        tester,
        Center(
          child: TextField(
            controller: c,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
        ),
      );
      final r = await runSteps(tester, [b.expect(text: 'Email', value: '@example.com', match: TextMatch.contains, timeout: 500)]);
      expect(r.status, BistStatus.passed, reason: firstError(r));
    });
  });

  group('Count', () {
    Widget list(int n) => ListView(children: [for (var i = 0; i < n; i++) ListTile(title: Text('Order $i'))]);

    testWidgets('number of rows on screen', (tester) async {
      await setUpScreen(tester, list(3));
      final r = await runSteps(tester, [b.expect(text: 'Order', match: TextMatch.contains, count: 3, timeout: 500)]);
      expect(r.status, BistStatus.passed, reason: firstError(r));
    });

    testWidgets('wrong count: reports the actual count', (tester) async {
      await setUpScreen(tester, list(3));
      final r = await runSteps(tester, [b.expect(text: 'Order', match: TextMatch.contains, count: 5, timeout: 300)]);
      expect(r.status, BistStatus.failed);
      expect(firstError(r), contains('Count is 3, expected 5'));
    });

    testWidgets('notExpect count', (tester) async {
      await setUpScreen(tester, list(2));
      final r = await runSteps(tester, [b.notExpect(text: 'Order', match: TextMatch.contains, count: 3, timeout: 300)]);
      expect(r.status, BistStatus.passed, reason: firstError(r));
    });
  });

  group('Checked / selected', () {
    testWidgets('checked: switch in a settings row, tap turns it on', (tester) async {
      await setUpScreen(tester, const _SwitchRow());
      final r = await runSteps(tester, [
        b.expect(text: 'Notifications', checked: false, timeout: 500),
        b.tap(text: 'Notifications'),
        b.expect(text: 'Notifications', checked: true, timeout: 1000),
      ]);
      expect(r.status, BistStatus.passed, reason: firstError(r));
    });

    testWidgets('wrong checked: reports the current state', (tester) async {
      await setUpScreen(tester, const _SwitchRow());
      final r = await runSteps(tester, [b.expect(text: 'Notifications', checked: true, timeout: 300)]);
      expect(r.status, BistStatus.failed);
      expect(firstError(r), contains('checked false'));
    });

    testWidgets('selected chip', (tester) async {
      await setUpScreen(
        tester,
        const Row(
          children: [
            ChoiceChip(label: Text('All'), selected: true),
            ChoiceChip(label: Text('Sent'), selected: false),
          ],
        ),
      );
      final r = await runSteps(tester, [b.expect(text: 'All', selected: true, timeout: 500), b.expect(text: 'Sent', selected: false, timeout: 500)]);
      expect(r.status, BistStatus.passed, reason: firstError(r));
    });

    testWidgets('selected tab (TabBar)', (tester) async {
      await setUpScreen(
        tester,
        const DefaultTabController(
          length: 2,
          child: TabBar(
            tabs: [
              Tab(text: 'Drafts'),
              Tab(text: 'Sent'),
            ],
          ),
        ),
      );
      final r = await runSteps(tester, [
        b.expect(text: 'Drafts', selected: true, timeout: 500),
        b.tap(text: 'Sent'),
        b.expect(text: 'Sent', selected: true, timeout: 1000),
      ]);
      expect(r.status, BistStatus.passed, reason: firstError(r));
    });
  });

  group('Running the tree', () {
    testWidgets('scripts that write data do not run on production', (tester) async {
      _provider.production = true;
      var taps = 0;
      await setUpScreen(
        tester,
        Center(
          child: ElevatedButton(onPressed: () => taps++, child: const Text('Send')),
        ),
      );
      final r = await runSteps(tester, [b.tap(text: 'Send')], writes: true);
      expect(r.status.isFailure, isTrue);
      expect(firstError(r), contains('Production'));
      expect(taps, 0);
    });

    testWidgets('sequence: after a failure the rest is skipped', (tester) async {
      await setUpScreen(tester, const Center(child: Text('Home')));
      final r = await run(
        tester,
        TestSequence(
          name: 'Sequence',
          cases: [
            TestUnit(
              name: 'Fails',
              steps: [b.expect(text: 'Missing', timeout: 200)],
            ),
            TestUnit(
              name: 'After',
              steps: [b.expect(text: 'Home', timeout: 200)],
            ),
          ],
        ),
      );
      expect(r.units.map((u) => u.status).toList(), [BistStatus.failed, BistStatus.skipped]);
    });

    testWidgets('finds text above the Navigator (app notification layer)', (tester) async {
      await setUpScreen(
        tester,
        const Center(child: Text('Home')),
        builder: (c, child) => Stack(
          children: [
            child!,
            const Positioned(top: 40, left: 0, right: 0, child: Material(child: Text('Please enter the username'))),
          ],
        ),
      );
      final r = await runSteps(tester, [b.expect(text: 'Please enter the username', timeout: 500)]);
      expect(r.status, BistStatus.passed, reason: firstError(r));
    });

    testWidgets('input, then read it back with getText', (tester) async {
      await setUpScreen(
        tester,
        const Center(
          child: TextField(decoration: InputDecoration(labelText: 'Name')),
        ),
      );
      final r = await runSteps(tester, [
        b.input('Bob', text: 'Name'),
        b.getText('n', text: 'Name', type: WidgetType.input),
        b.expect(text: 'Name', value: '{{n}}', timeout: 500),
      ]);
      expect(r.status, BistStatus.passed, reason: firstError(r));
    });

    testWidgets('dropdown: input picks the item', (tester) async {
      await setUpScreen(tester, const _Dropdown());
      final r = await runSteps(tester, [b.input('Blue', id: 'color'), b.expect(text: 'Picked Blue', timeout: 1000)]);
      expect(r.status, BistStatus.passed, reason: firstError(r));
    });
  });

  group('BistProvider', () {
    testWidgets('default navigation: nav / back / route with Bist.navigatorObserver', (tester) async {
      await setUpScreen(
        tester,
        const Center(child: Text('Home')),
        routes: {'/orders': (_) => const Scaffold(body: Center(child: Text('Orders')))},
      );
      final r = await runSteps(tester, [
        b.nav('/orders'),
        b.expect(text: 'Orders', route: '/orders', timeout: 1000),
        b.back(),
        b.expect(text: 'Home', timeout: 1000),
      ]);
      expect(r.status, BistStatus.passed, reason: firstError(r));
    });

    testWidgets('env, test data and app values in placeholders', (tester) async {
      Bist.instance.values['company'] = () => 'ACME';
      await setUpScreen(tester, const Center(child: Text('Alice · admin01 · ACME')));
      final r = await runSteps(tester, [b.expect(text: '{{env:user.name}} · {{tc:Admin.userName}} · {{env:company}}', timeout: 500)]);
      expect(r.status, BistStatus.passed, reason: firstError(r));
    });

    testWidgets('logs: expectLog and getLog with a path', (tester) async {
      await setUpScreen(tester, Center(child: _LogButton(_provider)));
      final r = await runSteps(tester, [
        b.tap(text: 'Login'),
        b.expectLog('POST /api/login', level: LogLevel.success, timeout: 1000),
        b.getLog('uid', '/api/login', path: 'responseBody.data.userId', timeout: 1000),
        b.log('uid = {{uid}}'),
      ]);
      expect(r.status, BistStatus.passed, reason: firstError(r));
      expect(r.units.single.steps.last.cmd, contains('uid = 42'));
    });

    testWidgets('server switch through the provider', (tester) async {
      await setUpScreen(tester, const Center(child: Text('Home')));
      final r = await runSteps(tester, [b.server('DEV'), b.getEnv('s', 'server.name'), b.log('{{s}}')]);
      expect(r.status, BistStatus.passed, reason: firstError(r));
      expect(r.units.single.steps.last.cmd, contains('DEV'));
    });

    testWidgets('custom widget: textsOf / isButton from the provider', (tester) async {
      var taps = 0;
      await setUpScreen(
        tester,
        Center(
          child: _IconOnlyButton(label: 'Add order', onTap: () => taps++),
        ),
      );
      final r = await runSteps(tester, [b.tap(text: 'Add order', type: WidgetType.button)]);
      expect(r.status, BistStatus.passed, reason: firstError(r));
      expect(taps, 1);
    });

    testWidgets('a feature the app does not support fails with a clear message', (tester) async {
      await Bist.init(); // plain provider: no pickFile
      await setUpScreen(tester, const Center(child: Text('Home')));
      final r = await runSteps(tester, [b.pickFile('https://example.com/a.pdf')]);
      expect(r.status, BistStatus.failed);
      expect(firstError(r), contains('pickFile is not supported'));
    });
  });

  group('Fake server', () {
    testWidgets('mockApi returns 500 with the server message; removed when the run ends', (tester) async {
      await setUpScreen(tester, const _ApiButton());
      final r = await runSteps(tester, [
        b.mockApi('api/orders', status: 500, body: '{"message":"Server busy"}'),
        b.tap(text: 'Load'),
        b.expect(text: 'E500: Server busy', timeout: 1000),
      ]);
      expect(r.status, BistStatus.passed, reason: firstError(r));
      expect(_provider.hook, isNull, reason: 'the mock must be removed after the run');
    });

    testWidgets('mockApi success body; times: 1 then real again', (tester) async {
      await setUpScreen(tester, const _ApiButton());
      final r = await runSteps(tester, [
        b.mockApi('api/orders', body: '{"total":2}', times: 1, method: 'GET'),
        b.tap(text: 'Load'),
        b.expect(text: '200 {"total":2}', timeout: 1000),
        b.tap(text: 'Load'),
        b.expect(text: 'real', timeout: 1000),
      ]);
      expect(r.status, BistStatus.passed, reason: firstError(r));
    });

    testWidgets('offline: requests fail like no network', (tester) async {
      await setUpScreen(tester, const _ApiButton());
      final r = await runSteps(tester, [b.offline(), b.tap(text: 'Load'), b.expect(text: 'No network', timeout: 1000)]);
      expect(r.status, BistStatus.passed, reason: firstError(r));
    });
  });

  group('Script check', () {
    test('new commands: JSON round trip', () {
      final g = TestGroup(
        id: 'v',
        name: 'v',
        cases: [
          TestUnit(
            name: 'u',
            steps: [
              b.expect(text: 'Order', match: TextMatch.contains, count: 2, checked: true, selected: false),
              b.mockApi('api/x', status: 404, delay: 100, times: 2, method: 'GET'),
              b.offline(on: false),
              b.resetApi(),
            ],
          ),
        ],
      );
      final back = TestGroup.decode(g.encode());
      expect(back.encode(), g.encode());
    });

    test('JSON made by bist.ts (the editor): the Dart model reads it and writes it back the same', () {
      // fixtures/bist_parity.json is generated from tools/editor/bist.ts – keeps the TS and Dart checks in sync
      final text = File('test/fixtures/bist_parity.json').readAsStringSync();
      final g = TestGroup.decode(text);
      expect(jsonDecode(g.encode()), jsonDecode(text));
    });

    test('invalid values are refused', () {
      expect(() => b.mockApi('api/x', status: 700), throwsArgumentError);
      expect(() => b.mockApi('api/x', method: 'FETCH'), throwsArgumentError);
      expect(() => b.expect(text: '([', match: TextMatch.regex), throwsArgumentError);
      expect(() => b.expect(text: 'a', count: -1), throwsArgumentError);
      expect(() => b.expect(route: '/x', checked: true), throwsArgumentError);
    });
  });
}

class _SwitchRow extends StatefulWidget {
  const _SwitchRow();

  @override
  State<_SwitchRow> createState() => _SwitchRowState();
}

class _SwitchRowState extends State<_SwitchRow> {
  bool on = false;

  @override
  Widget build(BuildContext context) => ListView(
    children: [SwitchListTile(title: const Text('Notifications'), value: on, onChanged: (v) => setState(() => on = v))],
  );
}

class _Dropdown extends StatefulWidget {
  const _Dropdown();

  @override
  State<_Dropdown> createState() => _DropdownState();
}

class _DropdownState extends State<_Dropdown> {
  String? value;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      DropdownButton<String>(
        key: const ValueKey('color'),
        value: value,
        hint: const Text('Color'),
        items: const [
          DropdownMenuItem(value: 'Red', child: Text('Red')),
          DropdownMenuItem(value: 'Blue', child: Text('Blue')),
        ],
        onChanged: (v) => setState(() => value = v),
      ),
      if (value != null) Text('Picked $value'),
    ],
  );
}

/// Custom button that draws no text – the provider gives its label
class _IconOnlyButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _IconOnlyButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap, child: const Icon(Icons.add, size: 48));
}

class _LogButton extends StatelessWidget {
  final _TestProvider provider;

  const _LogButton(this.provider);

  @override
  Widget build(BuildContext context) => ElevatedButton(
    onPressed: () => provider.log(
      'POST /api/login',
      level: 'success',
      data: {
        'responseBody': jsonEncode({
          'data': {'userId': 42},
        }),
      },
    ),
    child: const Text('Login'),
  );
}

/// Button calling a fake HTTP client that asks the provider's hook, then shows "status body" or the error
class _ApiButton extends StatefulWidget {
  const _ApiButton();

  @override
  State<_ApiButton> createState() => _ApiButtonState();
}

class _ApiButtonState extends State<_ApiButton> {
  String result = '';

  Future<void> load() async {
    final mock = await _provider.hook?.call('GET', Uri.parse('https://example.test/api/orders'));
    setState(
      () => result = switch (mock) {
        BistOffline() => 'No network',
        BistMockResponse(isError: true) => 'E${mock.status}: ${mock.message}',
        BistMockResponse() => '${mock.status} ${mock.body}',
        null => 'real',
      },
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ElevatedButton(onPressed: load, child: const Text('Load')),
      Text(result),
    ],
  );
}
