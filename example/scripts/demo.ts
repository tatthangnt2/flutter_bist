// Exported to example/assets/bist/demo.json with
// `node bin/bist.mjs example/scripts example/assets/bist` (needs `npm install` in tools/editor once).
import { TestGroup, TestSequence, TestUnit, WidgetType, expect, input, nav, notExpect, tap, printJson } from 'flutter_bist';

const login = (user: string, pass: string) => [
  input(user, { text: 'Username' }),
  input(pass, { text: 'Password' }),
  tap({ text: 'SIGN IN', type: WidgetType.button }),
];

printJson(
  TestGroup({
    id: 'demo',
    name: 'Demo app',
    cases: [
      TestGroup({
        id: 'login',
        name: 'Login',
        pre: [nav('/login')],
        cases: [
          TestUnit({ id: 'login.empty', name: 'Missing fields', steps: [...login('', ''), expect({ text: 'Please enter your username and password.' })] }),
          TestUnit({ id: 'login.wrong', name: 'Wrong password', steps: [...login('alice', 'x'), expect({ text: 'Wrong password.' })] }),
        ],
      }),
      TestSequence({
        id: 'orders',
        name: 'Orders',
        cases: [
          TestUnit({ id: 'orders.open', name: 'Sign in', steps: [nav('/login'), ...login('alice', 'secret'), expect({ route: '/orders', timeout: 3000 })] }),
          TestUnit({
            id: 'orders.add',
            name: 'Add an order',
            steps: [expect({ text: '^Order \\d+$', match: 'regex', count: 2 }), tap({ icon: 'add' }), expect({ text: 'Order 3' }), notExpect({ text: 'Order 4' })],
          }),
        ],
      }),
    ],
  }),
);
