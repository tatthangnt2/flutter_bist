import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bist/flutter_bist.dart';
import 'package:flutter_bist/ui.dart';

/// A tiny app with a login screen and a list – and BIST scripts in assets/bist/ that test it.
/// Run it, tap the floating "BIST" button, then ▶ a script. Or run a script on start:
/// `flutter run --dart-define=BIST_RUN=demo`
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Bist.init(); // plain Flutter app: the default BistProvider is enough
  await Bist.instance.loadAssets('assets/bist/');
  unawaited(Bist.instance.autoRun());
  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'BIST demo',
    navigatorObservers: [Bist.navigatorObserver],
    builder: BistPanel.overlay,
    initialRoute: '/login',
    routes: {'/login': (_) => const LoginPage(), '/orders': (_) => const OrdersPage()},
  );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _user = TextEditingController(), _pass = TextEditingController();
  String? _error;

  void _login() {
    if (_user.text.isEmpty || _pass.text.isEmpty) return setState(() => _error = 'Please enter your username and password.');
    if (_pass.text != 'secret') return setState(() => _error = 'Wrong password.');
    Navigator.of(context).pushReplacementNamed('/orders');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Login')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TextField(
          controller: _user,
          decoration: const InputDecoration(labelText: 'Username'),
        ),
        TextField(
          controller: _pass,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password'),
        ),
        const SizedBox(height: 16),
        if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
        FilledButton(onPressed: _login, child: const Text('SIGN IN')),
      ],
    ),
  );
}

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  final _orders = <String>['Order 1', 'Order 2'];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Orders'),
      actions: [IconButton(tooltip: 'Log out', icon: const Icon(Icons.logout), onPressed: () => Navigator.of(context).pushReplacementNamed('/login'))],
    ),
    floatingActionButton: FloatingActionButton(onPressed: () => setState(() => _orders.add('Order ${_orders.length + 1}')), child: const Icon(Icons.add)),
    body: ListView(children: [for (final o in _orders) ListTile(title: Text(o))]),
  );
}
