import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bist/flutter_bist.dart' hide expect;
import 'package:flutter_bist/flutter_bist.dart' as b;
import 'package:flutter_test/flutter_test.dart';

/// Provider of the tests: fake HTTP client, logs, test data, servers, a custom widget
class _TestProvider extends BistProvider {
  bool production = false;
  final _tmp = Directory.systemTemp.createTempSync('bist_test');

  @override
  Future<Directory> tempDir() async => _tmp;
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
  WidgetType? widgetOf(Widget w) => w is _IconOnlyButton ? WidgetType.button : super.widgetOf(w);
}

final _provider = _TestProvider();

void main() {
  var gid = 0;

  setUp(() {
    Bist.init(provider: _provider);
    _provider.production = false;
    Bist.instance.screenshots = false;
    Bist.instance.skipTester = false;
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
  Future<BistResult> run(WidgetTester tester, BistUnit c) async {
    Bist.instance.add(BistSuite(id: 'g${gid++}', name: 'Test group', units: [c]));
    BistResult? rs;
    Bist.instance.run(c).then((r) => rs = r).ignore();
    // Runner timeouts use real time: pump until done (at most 20 real seconds)
    final until = DateTime.now().add(const Duration(seconds: 20));
    while (rs == null && DateTime.now().isBefore(until)) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(rs, isNotNull, reason: 'the runner did not finish');
    return rs!;
  }

  Future<BistResult> runSteps(WidgetTester tester, List<BistAction> steps, {bool writes = false}) =>
      run(tester, BistCase(name: 'Test', steps: steps, writes: writes));

  String? firstError(BistResult r) => r.cases.where((u) => u.status.isFailure).firstOrNull?.error;

  /// Content of `<phase>.log` in the folder of the only test of [r]
  String log(BistResult r, String phase) => File('${r.cases.single.dir}/$phase.log').readAsStringSync();

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

    testWidgets('type: checkbox / radio / dropdown', (tester) async {
      await setUpScreen(
        tester,
        Column(
          children: [
            CheckboxListTile(title: const Text('Remember me'), value: true, onChanged: (_) {}),
            // ignore: deprecated_member_use
            RadioListTile<int>(title: const Text('Option B'), value: 2, groupValue: 2, onChanged: (_) {}),
            DropdownButton<String>(
              value: 'Leave',
              items: const [DropdownMenuItem(value: 'Leave', child: Text('Leave'))],
              onChanged: (_) {},
            ),
            const Text('Plain'),
          ],
        ),
      );
      final r = await runSteps(tester, [
        b.expect(text: 'Remember me', type: WidgetType.checkbox, checked: true, timeout: 500),
        b.expect(text: 'Option B', type: WidgetType.radio, checked: true, timeout: 500),
        b.expect(text: 'Leave', type: WidgetType.dropdown, timeout: 500),
        b.notExpect(text: 'Plain', type: WidgetType.checkbox, timeout: 300),
        b.notExpect(text: 'Remember me', type: WidgetType.radio, timeout: 300),
      ]);
      expect(r.status, BistStatus.passed, reason: firstError(r));
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
        BistSequence(
          name: 'Sequence',
          units: [
            BistCase(
              name: 'Fails',
              steps: [b.expect(text: 'Missing', timeout: 200)],
            ),
            BistCase(
              name: 'After',
              steps: [b.expect(text: 'Home', timeout: 200)],
            ),
          ],
        ),
      );
      expect(r.cases.map((u) => u.status).toList(), [BistStatus.failed, BistStatus.skipped]);
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
      expect(log(r, 'step').trim().split('\n').last, contains('uid = 42'));
    });

    testWidgets('server switch through the provider', (tester) async {
      await setUpScreen(tester, const Center(child: Text('Home')));
      final r = await runSteps(tester, [b.server('DEV'), b.getEnv('s', 'server.name'), b.log('{{s}}')]);
      expect(r.status, BistStatus.passed, reason: firstError(r));
      expect(log(r, 'step').trim().split('\n').last, contains('DEV'));
    });

    testWidgets('result tree: the root is the top suite, with tests run before the target and the target\'s nodes', (tester) async {
      await setUpScreen(tester, const Center(child: Text('Home')));
      final target = BistSequence(
        name: 'Inner',
        units: [
          BistCase(name: 'B', steps: [b.wait(10)]),
          BistCase(name: 'C', steps: [b.expect(text: 'Missing', timeout: 200)]),
          BistCase(name: 'D', steps: [b.wait(10)]),
        ],
      );
      final top = BistSequence(id: 'g${gid++}', name: 'Tree', units: [BistCase(name: 'A', steps: [b.wait(10)]), target]);
      Bist.instance.add(top);
      BistResult? rs;
      Bist.instance.run(target).then((x) => rs = x).ignore();
      final until = DateTime.now().add(const Duration(seconds: 20));
      while (rs == null && DateTime.now().isBefore(until)) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final r = rs!;
      expect(r.unit, same(top));
      expect(r.target, same(target));
      expect(r.children.map((c) => c.unit.name), ['A', 'Inner']);
      expect(r.cases.map((c) => c.status), [BistStatus.passed, BistStatus.passed, BistStatus.failed, BistStatus.skipped]);
      expect(r.find(target)!.status, BistStatus.failed);
      expect(r.status, BistStatus.failed);
      expect(r.progress, 1);
      expect(r.find(target)!.children.map((c) => c.number), [for (final n in [1, 2, 3]) '${Bist.instance.numberOf(target)}.$n']);
    });

    testWidgets('result folder: <run>/<number>/ with pre / step / after.log and error.log; a suite pre goes to the next test', (tester) async {
      await setUpScreen(tester, const Center(child: Text('Home')));
      final c = BistCase(
        name: 'Fails',
        pre: [b.log('case pre')],
        steps: [b.log('one'), b.expect(text: 'Missing', timeout: 200)],
        after: [b.log('clean up')],
      );
      Bist.instance.add(BistSuite(id: 'g${gid++}', name: 'Folder', pre: [b.log('suite pre')], units: [c]));
      BistResult? rs;
      Bist.instance.run(c).then((x) => rs = x).ignore();
      final until = DateTime.now().add(const Duration(seconds: 20));
      while (rs == null && DateTime.now().isBefore(until)) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final r = rs!;
      expect(r.status, BistStatus.failed);
      final number = r.cases.single.number;
      expect(r.cases.single.dir, '${r.dir}/$number');
      expect(RegExp(r'/bist/\d{4}-\d\d-\d\d \d\d-\d\d-\d\d( \(\d+\))?$').hasMatch(r.dir!), isTrue, reason: r.dir);
      final pre = log(r, 'pre');
      expect(pre, contains('suite pre'));
      expect(pre, contains('_1 ✓ log')); // the suite's action: <suite number>_1
      expect(pre, contains('1 ✓ log "case pre"'));
      final step = log(r, 'step');
      expect(step, contains('1 ✓ log "one"'));
      expect(step, contains('2 ✗ expect'));
      expect(step, contains('→ Not found'));
      expect(log(r, 'after'), contains('clean up'));
      final error = File('${r.cases.single.dir}/error.log').readAsStringSync().trim();
      expect(error, r.cases.single.error);
      expect(error, startsWith('Not found'));
    });

    testWidgets('custom widget: textsOf / widgetOf from the provider', (tester) async {
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
      final g = BistSuite(
        id: 'v',
        name: 'v',
        units: [
          BistCase(
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
      final back = BistSuite.decode(g.encode());
      expect(back.encode(), g.encode());
    });

    test('JSON made by bist.ts (the editor): the Dart model reads it and writes it back the same', () {
      // fixtures/bist_parity.json is generated from tools/editor/bist.ts – keeps the TS and Dart checks in sync
      final text = File('test/fixtures/bist_parity.json').readAsStringSync();
      final g = BistSuite.decode(text);
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

  group('Tests that need a tester', () {
    test('needsTester: manual, confirm / ask in steps, loops or the pre / after of a group', () {
      final manual = BistCase(name: 'm', manual: 'Face ID');
      final confirm = BistCase(name: 'c', steps: [b.confirm('Did it ring?')]);
      final inLoop = BistCase(
        name: 'l',
        steps: [
          b.loop(1, 2, [b.ask('code', 'OTP?')]),
        ],
      );
      final plain = BistCase(name: 'p', steps: [b.wait(1)]);
      final underPre = BistCase(name: 'u', steps: [b.wait(1)]);
      BistSuite(name: 'g', pre: [b.confirm('Ready?')], units: [underPre]);
      BistSuite(name: 'root', units: [manual, confirm, inLoop, plain]);
      expect([manual, confirm, inLoop, plain, underPre].map((u) => u.needsTester), [true, true, true, false, true]);
    });

    testWidgets('skipTester: tests with confirm / ask are skipped, the others run', (tester) async {
      await setUpScreen(tester, const Center(child: Text('Home')));
      Bist.instance.skipTester = true;
      final r = await run(
        tester,
        BistSuite(
          name: 'Mixed',
          units: [
            BistCase(name: 'Asks', steps: [b.confirm('Did it ring?')]),
            BistCase(
              name: 'Plain',
              steps: [b.expect(text: 'Home', timeout: 500)],
            ),
          ],
        ),
      );
      expect(r.cases.map((u) => u.status), [BistStatus.skipped, BistStatus.passed]);
      expect(r.cases.first.error, contains('needs a tester'));
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
