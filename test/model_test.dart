import 'package:flutter_bist/flutter_bist.dart';
import 'package:flutter_test/flutter_test.dart' as t;

List<BistAction> login(String user, String pass) => [
  input(user, text: 'Username'),
  input(pass, text: 'Password'),
  tap(text: 'SIGN IN', type: WidgetType.button),
];

void main() {
  final script = BistSuite(
    id: 'app',
    name: 'App',
    pre: [server('DEV')],
    units: [
      BistSuite(
        id: 'login',
        name: 'Login',
        pre: [
          expect(text: 'SIGN IN', timeout: 500, onError: [runTest('logout')]),
        ],
        units: [
          BistCase(
            name: 'Missing fields',
            steps: [
              ...login('', ''),
              expect(text: 'Please enter username and password.'),
            ],
          ),
          BistCase(
            id: 'login.admin',
            name: 'Admin',
            steps: [
              ...login(tc('Admin', 'userName'), 'x'),
              notExpect(text: 'SIGN IN'),
            ],
          ),
          BistCase(name: 'Google', manual: 'OS account picker'),
        ],
      ),
      BistSequence(
        name: 'Leave request',
        writes: true,
        minVersion: '1.0.20+140',
        units: [
          BistCase(
            name: 'Create',
            steps: [
              tapDouble(icon: 'add', route: '/leave'),
              wait(100),
            ],
          ),
          BistCase(
            name: 'Detail',
            maxVersion: '2.0.0',
            steps: [
              swipe(SwipeDirection.up),
              expectLog('Detail', level: LogLevel.success),
            ],
          ),
        ],
      ),
      BistCase(
        id: 'logout',
        name: 'Logout',
        steps: [
          tapLong(id: 'logout'),
          back(),
        ],
      ),
    ],
  );

  t.group('Script tree', () {
    t.test('numbers, parent, writes', () {
      final seq = script.units[1] as BistSequence;
      t.expect(seq.units[1].number, '2.2');
      t.expect(seq.units[1].isWrites, true);
      t.expect(script.findId('login.admin')!.number, '1.2');
      t.expect(script.findNumber('2.1')!.name, 'Create');
      t.expect(script.cases.length, 6);
      t.expect(script.runTests, {'logout'});
    });

    t.test('JSON round trip', () {
      final back = BistSuite.decode(script.encode());
      t.expect(back.toRootJson(), script.toRootJson());
      t.expect(back.units[1], t.isA<BistSequence>());
      t.expect((back.units[0] as BistSuite).units[2].manual, t.isA<String>());
      t.expect(BistSuite.validate(script.toRootJson(), fileName: 'scripts/app.bist'), t.isEmpty);
      t.expect(BistSuite.validate(script.toRootJson(), fileName: 'other.json'), t.isNotEmpty);
    });

    t.test('version 1.0.0+10', () {
      t.expect(TestVersion.parse('1.0.21+146').compareTo(TestVersion.parse('1.0.21+140')), 1);
      t.expect(TestVersion.parse('1.0.21').compareTo(TestVersion.parse('1.0.21+1')), 0);
      t.expect(() => TestVersion.parse('1.0'), t.throwsFormatException);
      t.expect(TestVersion.tryFrom('1.2.0-beta', 15).toString(), '1.2.0+15');
      final seq = script.units[1];
      t.expect(seq.appliesTo(TestVersion.parse('1.0.20+139')), false);
      t.expect(seq.appliesTo(TestVersion.parse('1.0.21+1')), true);
      t.expect((seq as BistSuite).units[1].appliesTo(TestVersion.parse('2.0.1')), false);
    });

    t.test('invalid scripts are reported', () {
      t.expect(() => tap(), t.throwsArgumentError);
      t.expect(() => expect(), t.throwsArgumentError);
      t.expect(
        () => expect(
          text: 'A',
          onError: [
            expect(text: 'B', onError: [back()]),
          ],
        ),
        t.throwsArgumentError,
      );
      final errors = BistSuite.validate({
        'schema': kTestScriptSchema,
        'type': 'suite',
        'id': 'a',
        'name': 'a',
        'units': [
          {
            'type': 'case',
            'id': 'x',
            'name': 'u',
            'steps': [
              {'cmd': 'see', 'text': 'A'},
            ],
          },
          {'type': 'case', 'id': 'x', 'name': 'v', 'minVersion': '1.0', 'steps': []},
        ],
      });
      t.expect(errors, t.hasLength(t.greaterThanOrEqualTo(4)));
      t.expect(errors.join('\n'), t.contains('unknown command'));
      t.expect(errors.join('\n'), t.contains('is duplicated'));
      t.expect(() => BistSuite.fromJson({'schema': kTestScriptSchema + 1, 'type': 'suite', 'id': 'a', 'name': 'a', 'units': []}), t.throwsUnsupportedError);
    });

    t.test('input checks, loops, generated data, dates', () {
      final steps = [
        expect(text: 'Code', type: WidgetType.input, value: 'AB', focused: false, obscured: true, maxLength: 10),
        notExpect(text: 'Code', focused: true),
        inputDate('{{date:+1}}', text: 'Leave date'),
        inputDateRange('01/11/2026', '05/11/2026', text: 'From'),
        randInt('no', 1, 99, format: 'Order {value}'),
        randText('code', 3, 8, chars: 'ABC', format: 'BIST-{value}'),
        loop(1, 3, [input('Line {{i}}', text: 'Note'), runTest('logout')]),
        loopWhile(expect(text: 'Load more', timeout: 500), [swipe(SwipeDirection.up)], max: 5),
      ];
      final g = BistSuite(
        id: 'g',
        name: 'g',
        units: [
          BistCase(id: 'logout', name: 'x', steps: [back()]),
          BistCase(name: 'u', steps: steps),
        ],
      );
      t.expect(BistSuite.validate(g.toRootJson()), t.isEmpty);
      final back2 = BistSuite.decode(g.encode());
      t.expect(back2.toRootJson(), g.toRootJson());
      t.expect(g.runTests, {'logout'});
      final st = (back2.units[1] as BistCase).steps;
      t.expect(st[0].fieldValue, 'AB');
      t.expect(st[0].focused, false);
      t.expect(st[1].focused, true);
      t.expect(st[6].steps.length, 2);
      t.expect(st[7].condition!.cmd, 'expect');
      t.expect(st[4].describe(), 'randInt {{no}} = 1..99 "Order {value}"');
      t.expect(kTestValuePattern.allMatches('{{no}} {{i}}').map((m) => m[1]).toList(), ['no', 'i']);
    });

    t.test('invalid new commands are reported', () {
      t.expect(() => expect(value: 'A'), t.throwsArgumentError);
      t.expect(() => randInt('now', 1, 2), t.throwsArgumentError);
      t.expect(() => randInt('x', 5, 2), t.throwsArgumentError);
      t.expect(() => randText('x', 5, 2), t.throwsArgumentError);
      t.expect(() => loop(1, 2, []), t.throwsArgumentError);
      t.expect(() => loopWhile(tap(text: 'A'), [back()]), t.throwsArgumentError);
      t.expect(() => loopWhile(expect(text: 'A'), [back()], max: 0), t.throwsArgumentError);
      t.expect(() => pickFile('http://a.com/x.pdf'), t.throwsArgumentError);
      t.expect(pickFile('https://a.com/files/sample.pdf', name: 'sample.pdf').describe(), 'pickFile https://a.com/files/sample.pdf → "sample.pdf"');
    });

    t.test('read values: getText, getLog, getEnv, env()', () {
      final steps = [
        getText('fullName', text: 'Full name', type: WidgetType.input),
        getLog('uid', 'login', path: 'responseBody.data.userId', level: LogLevel.success, timeout: 8000),
        getEnv('ver', 'app.version'),
        expect(text: env('user.name')),
        input('{{uid}} - {{fullName}}', text: 'Note'),
      ];
      final g = BistSuite(
        id: 'g',
        name: 'g',
        units: [BistCase(name: 'u', steps: steps)],
      );
      t.expect(BistSuite.validate(g.toRootJson()), t.isEmpty);
      t.expect(BistSuite.decode(g.encode()).toRootJson(), g.toRootJson());
      t.expect(steps[1].describe(), 'getLog {{uid}} ← log "login" responseBody.data.userId (success)');
      t.expect(steps[2].describe(), 'getEnv {{ver}} ← app.version');
      t.expect(kTestValuePattern.allMatches('{{env:user.name}} {{uid}}').map((m) => m[1]).toList(), ['env:user.name', 'uid']);
      // no secrets
      t.expect(() => getEnv('x', 'user.accessToken'), t.throwsArgumentError);
      t.expect(() => getLog('x', 'login', path: 'requestHeaders.Authorization'), t.throwsArgumentError);
      t.expect(() => getLog('x', 'login', path: 'requestBody.password'), t.throwsArgumentError);
      t.expect(() => getText('date', text: 'A'), t.throwsArgumentError);
    });

    t.test('print, notify, ask the tester', () {
      final steps = [
        log('userId = {{uid}}'),
        toast('Creating the order'),
        confirm('Is the "Send" button color right?', yes: 'Right', no: 'Wrong', timeout: 60000),
        ask('otp', 'Type the OTP sent to the phone', hint: '6 digits'),
        input('{{otp}}', text: 'OTP'),
      ];
      final g = BistSuite(
        id: 'g',
        name: 'g',
        units: [BistCase(name: 'u', steps: steps)],
      );
      t.expect(BistSuite.validate(g.toRootJson()), t.isEmpty);
      t.expect(BistSuite.decode(g.encode()).toRootJson(), g.toRootJson());
      t.expect(steps[2].describe(), 'confirm "Is the "Send" button color right?"');
      t.expect(steps[3].describe(), 'ask {{otp}} ← "Type the OTP sent to the phone"');
      t.expect(() => ask('now', 'x'), t.throwsArgumentError);
      t.expect(() => log(''), t.throwsArgumentError);
    });

    t.test('placeholders', () {
      t.expect(kTestValuePattern.allMatches('BIST {{now}} {{date:+1}} {{tc:A.b}} {{x-1}}').map((m) => m[1]).toList(), ['now', 'date:+1', 'tc:A.b']);
    });
  });

  t.test('each command is a BistAction subclass, the command name is its constructor', () {
    final a = tap(text: 'Send', type: WidgetType.button);
    t.expect(a, t.isA<TapBistAction>());
    t.expect(a.toJson(), TapBistAction(text: 'Send', type: WidgetType.button).toJson());
    t.expect(a.toJson(), {'cmd': 'tap', 'text': 'Send', 'type': 'button'});
    t.expect(input('abc', text: 'User'), t.isA<InputBistAction>());
    t.expect(loop(1, 2, [wait(10)]), t.isA<LoopBistAction>());
    t.expect(BistAction.fromJson({'cmd': 'tap', 'text': 'Send'}).toJson(), tap(text: 'Send').toJson());
    t.expect(() => TapBistAction(), t.throwsArgumentError);
  });

  t.test('command classes: own parameters in args, shared ones through super parameters – same JSON as before', () {
    t.expect(input('abc', text: 'User', shot: true).toJson(), {'cmd': 'input', 'value': 'abc', 'text': 'User', 'shot': true});
    t.expect(expect(text: 'User', type: WidgetType.input, value: 'abc', focused: false).toJson(), {
      'cmd': 'expect',
      'text': 'User',
      'type': 'input',
      'value': 'abc',
      'focused': false,
    });
    t.expect(offline().toJson(), {'cmd': 'offline', 'on': true});
    t.expect(getLog('uid', 'login', timeout: 8000).toJson(), {'cmd': 'getLog', 'name': 'uid', 'tag': 'login', 'timeout': 8000});
    t.expect(swipe(SwipeDirection.up, text: 'List').toJson(), {'cmd': 'swipe', 'direction': 'up', 'text': 'List'});
    t.expect(wait(100).toJson(), {'cmd': 'wait', 'ms': 100});
    t.expect(tap(text: 'A', onError: [back()]).toJson(), {
      'cmd': 'tap',
      'text': 'A',
      'onError': [
        {'cmd': 'back'},
      ],
    });
  });

  t.test('BistAction.custom(cmd, json) builds a raw action (custom actions), cmd stays first and wins', () {
    final a = BistAction.custom('myCommand', {'cmd': 'other', 'text': 'A', 'level': 3});
    t.expect(a.cmd, 'myCommand');
    t.expect(a.toJson(), {'cmd': 'myCommand', 'text': 'A', 'level': 3});
    t.expect(a.toJson().keys.first, 'cmd');
    t.expect(a.text, 'A');
    t.expect(BistAction.custom('back').toJson(), {'cmd': 'back'});
  });
}
