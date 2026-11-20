// Exported to example/assets/bist/demo.json with
// `node bin/bist.mjs example/scripts example/assets/bist` (needs `npm install` in tools/editor once).
import { BistSuite, BistSequence, BistCase, WidgetType, expect, input, nav, notExpect, tap, printJson } from 'flutter_bist';

const login = (user: string, pass: string) => [
  input(user, { text: 'Username' }),
  input(pass, { text: 'Password' }),
  tap({ text: 'SIGN IN', type: WidgetType.button }),
];

printJson(
  BistSuite({
    id: 'demo',
    name: 'Demo app',
    units: [
      BistSuite({
        id: 'login',
        name: 'Login',
        pre: [nav('/login')],
        units: [
          BistCase({ id: 'login.empty', name: 'Missing fields', steps: [...login('', ''), expect({ text: 'Please enter your username and password.' })] }),
          BistCase({ id: 'login.wrong', name: 'Wrong password', steps: [...login('alice', 'x'), expect({ text: 'Wrong password.' })] }),
        ],
      }),
      BistSequence({
        id: 'orders',
        name: 'Orders',
        units: [
          BistCase({ id: 'orders.open', name: 'Sign in', steps: [nav('/login'), ...login('alice', 'secret'), expect({ route: '/orders', timeout: 3000 })] }),
          BistCase({
            id: 'orders.add',
            name: 'Add an order',
            steps: [expect({ text: '^Order \\d+$', match: 'regex', count: 2 }), tap({ icon: 'add' }), expect({ text: 'Order 3' }), notExpect({ text: 'Order 4' })],
          }),
        ],
      }),
    ],
  }),
);
