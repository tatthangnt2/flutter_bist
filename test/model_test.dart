import 'package:flutter_bist/flutter_bist.dart';
import 'package:flutter_test/flutter_test.dart' as t;

List<TestAction> login(String user, String pass) => [
  input(user, text: 'Username'),
  input(pass, text: 'Password'),
  tap(text: 'SIGN IN', type: WidgetType.button),
];

void main() {
  final script = TestGroup(
    id: 'app',
    name: 'App',
    pre: [server('DEV')],
    cases: [
      TestGroup(
        id: 'login',
        name: 'Login',
        pre: [
          expect(text: 'SIGN IN', timeout: 500, onError: [runTest('logout')]),
        ],
        cases: [
          TestUnit(
            name: 'Missing fields',
            steps: [
              ...login('', ''),
              expect(text: 'Please enter username and password.'),
            ],
          ),
          TestUnit(
            id: 'login.admin',
            name: 'Admin',
            steps: [
              ...login(tc('Admin', 'userName'), 'x'),
              notExpect(text: 'SIGN IN'),
            ],
          ),
          TestUnit(name: 'Google', manual: 'OS account picker'),
        ],
      ),
      TestSequence(
        name: 'Leave request',
        writes: true,
        minVersion: '1.0.20+140',
        cases: [
          TestUnit(
            name: 'Create',
            steps: [
              tapDouble(icon: 'add', route: '/leave'),
              wait(100),
            ],
          ),
          TestUnit(
            name: 'Detail',
            maxVersion: '2.0.0',
            steps: [
              swipe(SwipeDirection.up),
              expectLog('Detail', level: LogLevel.success),
            ],
          ),
        ],
      ),
      TestUnit(
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
      final seq = script.cases[1] as TestSequence;
      t.expect(seq.cases[1].number, '2.2');
      t.expect(seq.cases[1].isWrites, true);
      t.expect(script.findId('login.admin')!.number, '1.2');
      t.expect(script.findNumber('2.1')!.name, 'Create');
      t.expect(script.units.length, 6);
      t.expect(script.runTests, {'logout'});
    });

    t.test('JSON round trip', () {
      final back = TestGroup.decode(script.encode());
      t.expect(back.toRootJson(), script.toRootJson());
      t.expect(back.cases[1], t.isA<TestSequence>());
      t.expect((back.cases[0] as TestGroup).cases[2].manual, t.isA<String>());
      t.expect(TestGroup.validate(script.toRootJson(), fileName: 'scripts/app.bist'), t.isEmpty);
      t.expect(TestGroup.validate(script.toRootJson(), fileName: 'other.json'), t.isNotEmpty);
    });

    t.test('version 1.0.0+10', () {
      t.expect(TestVersion.parse('1.0.21+146').compareTo(TestVersion.parse('1.0.21+140')), 1);
      t.expect(TestVersion.parse('1.0.21').compareTo(TestVersion.parse('1.0.21+1')), 0);
      t.expect(() => TestVersion.parse('1.0'), t.throwsFormatException);
      t.expect(TestVersion.tryFrom('1.2.0-beta', 15).toString(), '1.2.0+15');
      final seq = script.cases[1];
      t.expect(seq.appliesTo(TestVersion.parse('1.0.20+139')), false);
      t.expect(seq.appliesTo(TestVersion.parse('1.0.21+1')), true);
      t.expect((seq as TestGroup).cases[1].appliesTo(TestVersion.parse('2.0.1')), false);
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
      final errors = TestGroup.validate({
        'schema': kTestScriptSchema,
        'type': 'group',
        'id': 'a',
        'name': 'a',
        'cases': [
          {
            'type': 'unit',
            'id': 'x',
            'name': 'u',
            'steps': [
              {'cmd': 'see', 'text': 'A'},
            ],
          },
          {'type': 'unit', 'id': 'x', 'name': 'v', 'minVersion': '1.0', 'steps': []},
        ],
      });
      t.expect(errors, t.hasLength(t.greaterThanOrEqualTo(4)));
      t.expect(errors.join('\n'), t.contains('unknown command'));
      t.expect(errors.join('\n'), t.contains('is duplicated'));
      t.expect(() => TestGroup.fromJson({'schema': kTestScriptSchema + 1, 'type': 'group', 'id': 'a', 'name': 'a', 'cases': []}), t.throwsUnsupportedError);
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
      final g = TestGroup(
        id: 'g',
        name: 'g',
        cases: [
          TestUnit(id: 'logout', name: 'x', steps: [back()]),
          TestUnit(name: 'u', steps: steps),
        ],
      );
      t.expect(TestGroup.validate(g.toRootJson()), t.isEmpty);
      final back2 = TestGroup.decode(g.encode());
      t.expect(back2.toRootJson(), g.toRootJson());
      t.expect(g.runTests, {'logout'});
      final st = (back2.cases[1] as TestUnit).steps;
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
      final g = TestGroup(
        id: 'g',
        name: 'g',
        cases: [TestUnit(name: 'u', steps: steps)],
      );
      t.expect(TestGroup.validate(g.toRootJson()), t.isEmpty);
      t.expect(TestGroup.decode(g.encode()).toRootJson(), g.toRootJson());
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
      final g = TestGroup(
        id: 'g',
        name: 'g',
        cases: [TestUnit(name: 'u', steps: steps)],
      );
      t.expect(TestGroup.validate(g.toRootJson()), t.isEmpty);
      t.expect(TestGroup.decode(g.encode()).toRootJson(), g.toRootJson());
      t.expect(steps[2].describe(), 'confirm "Is the "Send" button color right?"');
      t.expect(steps[3].describe(), 'ask {{otp}} ← "Type the OTP sent to the phone"');
      t.expect(() => ask('now', 'x'), t.throwsArgumentError);
      t.expect(() => log(''), t.throwsArgumentError);
    });

    t.test('placeholders', () {
      t.expect(kTestValuePattern.allMatches('BIST {{now}} {{date:+1}} {{tc:A.b}} {{x-1}}').map((m) => m[1]).toList(), ['now', 'date:+1', 'tc:A.b']);
    });
  });
}
