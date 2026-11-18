part of '../flutter_bist.dart';

/// Thrown by [BistProvider] methods for features the app doesn't support; the step fails with a clear message.
class BistUnsupportedError extends UnsupportedError {
  /// Name of the feature, e.g. `mockApi`
  final String feature;

  BistUnsupportedError(this.feature) : super('$feature is not supported by this app (override it in its BistProvider)');
}

/// One app log line, for `expectLog`, `getLog` and the "app errors" of a report
class BistLog {
  /// Short text to search in, e.g. `POST /api/login`
  final String tag;

  /// `debug`, `info`, `warn`, `error`, `damage`, `success` (see `LogLevel` in `model.dart`)
  final String level;
  final DateTime time;

  /// Any data (Map / List / String); `getLog(path: ...)` reads inside it
  final Object? data;

  const BistLog(this.tag, {this.level = 'info', required this.time, this.data});

  /// Error-level log (counted as an app error in the report)
  bool get isError => level == 'error' || level == 'damage';
}

/// Result of a faked request, given by the runner to [BistProvider.attachNetwork]
sealed class BistMockResult {
  const BistMockResult();
}

/// Fake response of `mockApi`
class BistMockResponse extends BistMockResult {
  final int status;

  /// Response body (JSON text), `'{}'` when the script didn't give one
  final String body;

  /// Error message found in the body (`message` / `error` / `title`), or the body itself when it is plain text – for apps that
  /// show the server's message
  final String? message;

  const BistMockResponse(this.status, this.body, {this.message});

  bool get isError => status >= 400;
}

/// No network (`offline`): the request should fail like a connection error
class BistOffline extends BistMockResult {
  const BistOffline();
}

/// Called by the app's HTTP layer for every request while mocking is on: a fake result, or `null` to send it for real
typedef BistNetworkHook = Future<BistMockResult?> Function(String method, Uri uri);

/// Connects BIST to an app: screen, navigation, servers, test data, logs, network mocking, file picking and custom widgets.
///
/// Every method has a default that works with any Flutter app (or throws [BistUnsupportedError] / returns `null` = not
/// supported), so an app or a UI library only overrides what it needs:
///
/// ```dart
/// class MyBistProvider extends BistProvider {
///   @override
///   String? get currentRoute => myRouter.location;
///
///   @override
///   List<String?>? textsOf(Widget w) => w is MyButton ? [w.label] : null;
/// }
///
/// Bist.init(provider: MyBistProvider());
/// ```
class BistProvider {
  BistProvider();

  // ── Screen, app ──

  /// Root of the widget tree to search in (includes dialogs and overlays above the Navigator)
  BuildContext get rootContext => WidgetsBinding.instance.rootElement!;

  /// Context for the tester dialogs of `confirm` / `ask` (must be below a Navigator)
  BuildContext? get dialogContext => Bist.navigatorObserver.navigator?.context;

  /// The app is started and shows its first screen – `BIST_RUN` auto runs wait for this
  bool get isReady => WidgetsBinding.instance.rootElement != null && Bist.navigatorObserver.navigator != null;

  /// App version `1.2.0+15` for `minVersion` / `maxVersion` (`null` = unknown, every script applies)
  String? get appVersion => null;

  /// Environment value for `getEnv` / `{{env:<key>}}`, e.g. `user.name` (`null` = unknown). `Bist.values` is checked first;
  /// secret-looking keys never reach here.
  String? env(String key) => null;

  /// Shows a short message (`toast` command)
  void toast(String message) {
    final context = dialogContext;
    if (context == null) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 3)));
  }

  /// Folder for screenshots of failed steps and sample files of `pickFile`
  Future<Directory> tempDir() async => Directory.systemTemp;

  // ── Navigation ──

  /// Route of the screen on top, e.g. `/orders/detail` (default: [Bist.navigatorObserver])
  String? get currentRoute => Bist.navigatorObserver.currentRoute;

  /// Opens route [path] (`nav` command). Default: `Navigator.pushNamed`.
  Future<void> go(String path) async {
    final nav = Bist.navigatorObserver.navigator;
    if (nav == null) throw StateError('No Navigator – add Bist.navigatorObserver to navigatorObservers');
    unawaited(nav.pushNamed(path));
  }

  /// Closes the top dialog / screen (`back` command); `false` when there is nothing to close
  Future<bool> back() async => await Bist.navigatorObserver.navigator?.maybePop() ?? false;

  /// Route of the screen that contains [e] (default: its `ModalRoute` name)
  String? routeOf(Element e) => ModalRoute.of(e)?.settings.name;

  // ── Servers (`server` command; scripts with `writes` never run on production) ──

  /// The current server is production – scripts that write data are refused. Default `false`.
  bool get isProduction => false;

  /// Name of the current server (shown in reports)
  String? get serverName => null;

  /// Switches to server [name] and waits until the app uses it; returns an error message or `null`
  Future<String?> switchServer(String name, Duration timeout) async => throw BistUnsupportedError('server');

  // ── Test data, logs ──

  /// Test data for `{{tc:<group>.<field>}}` (e.g. test accounts), `null` = unknown (the placeholder stays as is)
  String? testData(String group, String field) => null;

  /// Starts delivering app logs to [onLog] for `expectLog` / `getLog` / app errors; returns a function that stops it,
  /// or `null` when the app has no logs (default)
  void Function()? listenLogs(void Function(BistLog log) onLog) => null;

  /// Logs written before the run started (searched by `getLog` after the run's own logs)
  Iterable<BistLog> get logHistory => const [];

  // ── Network mocking (`mockApi`, `offline`, `resetApi`) ──

  /// Starts calling [hook] for every HTTP request of the app; the provider turns a [BistMockResult] into its HTTP client's
  /// response / error. Default: not supported.
  void attachNetwork(BistNetworkHook hook) => throw BistUnsupportedError('mockApi / offline');

  /// Stops calling the hook (end of the run)
  void detachNetwork() {}

  // ── File picking (`pickFile`) ──

  /// Queues the file at [url] for the next file / image picker of the app; returns a short description for the report
  Future<String> addPickFile(String url, {String? name}) async => throw BistUnsupportedError('pickFile');

  /// Restores the real pickers at the end of the run; returns how many queued files were never used
  int closePickFiles() => 0;

  // ── Custom widgets: `null` = not mine, the built-in Material / Cupertino reader decides ──

  /// Texts used to find [w]: visible text, tooltip, label / hint of an input…
  List<String?>? textsOf(Widget w) => null;

  /// [w] is a tappable button (for `type: button`)
  bool? isButton(Widget w) => null;

  /// [w] is a text input (for `type: input` and the input next to a label)
  bool? isInput(Widget w) => null;

  /// [w] is an image / icon (for `type: image`)
  bool? isImage(Widget w) => null;

  /// Button / input [w] is enabled
  bool? isEnabled(Widget w) => null;

  /// Checkbox / switch / radio [w] is on
  bool? checkedOf(Widget w) => null;

  /// Tab / chip / item [w] is selected
  bool? selectedOf(Widget w) => null;

  /// [w] is a dropdown: `input(value)` taps it, then taps the item with text `value`
  bool? isDropdown(Widget w) => null;

  /// `input` into a custom field: return a Future (error message or `null`) when you handled it, `null` to let BIST type
  /// into the field's `EditableText`
  Future<String?>? enterText(Element field, String value) => null;

  /// `inputDate` / `inputDateRange` into a custom date field: [text] is the date as written in the script (`dd/MM/yyyy`),
  /// [end] is set for ranges. Return a Future (error message or `null`), or `null` when [field] isn't a date field of yours.
  Future<String?>? inputDate(Element field, String text, DateTime date, {DateTime? end}) => null;
}

/// Tracks the top route for the default [BistProvider] – add it to `MaterialApp.navigatorObservers`
class BistNavigatorObserver extends NavigatorObserver {
  final _stack = <Route<dynamic>>[];

  /// Name of the top page route (dialogs / popups are skipped)
  String? get currentRoute {
    for (final r in _stack.reversed) {
      if (r is PageRoute && r.settings.name != null) return r.settings.name;
    }
    return null;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _stack.add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _stack.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _stack.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (newRoute == null) return;
    if (i >= 0) {
      _stack[i] = newRoute;
    } else {
      _stack.add(newRoute);
    }
  }
}
