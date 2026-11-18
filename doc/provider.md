# BistProvider

`BistProvider` connects the runner to an app. It is **one class**: every method has a default that works with a plain
Flutter app, or reports "not supported" for features that need app knowledge. Extend it and override what you need:

```dart
Bist.init(provider: MyBistProvider());
```

A UI library ships its own provider (extending `BistProvider` with its navigation, HTTP client and widgets); an app using that
library extends it further (e.g. to add a Dio adapter).

## Screen, app

| Method | Default | Override when |
|---|---|---|
| `rootContext` | `WidgetsBinding.rootElement` | You render into another root |
| `dialogContext` | the `Navigator` seen by `Bist.navigatorObserver` | `confirm` / `ask` dialogs need another Navigator |
| `isReady` | root element and a Navigator exist | `autoRun` must wait for login / splash |
| `appVersion` | `null` (every script applies) | You use `minVersion` / `maxVersion` – return `'1.2.0+15'` (see `TestVersion.tryFrom`) |
| `env(key)` | `null` | `getEnv` / `{{env:key}}`: `user.name`, `app.version`… (secret-looking keys never reach you) |
| `toast(message)` | `SnackBar` | You have your own toast |
| `tempDir()` | `Directory.systemTemp` | Screenshots / sample files should go elsewhere (e.g. `path_provider`) |

`Bist.instance.values['key'] = () => value;` is checked before `env` – handy for a few app values without a provider.
Built-in keys: `route`, `app.version`, `server.name`.

## Navigation

| Method | Default |
|---|---|
| `currentRoute` | name of the top `PageRoute` (needs `Bist.navigatorObserver` in `navigatorObservers`) |
| `go(path)` (`nav`) | `Navigator.pushNamed` |
| `back()` (`back`) | `Navigator.maybePop` |
| `routeOf(element)` (`route:` filter) | `ModalRoute.of(element).settings.name` |

With go_router / beamer / auto_route, override `currentRoute` and `go` with the router's location and navigation.

## Servers

| Method | Default |
|---|---|
| `isProduction` | `false` |
| `serverName` | `null` |
| `switchServer(name, timeout)` (`server`) | not supported |

A script (or group) with `writes: true` creates or changes data: BIST refuses to run its steps while `isProduction` is
true. Return `true` when you aren't sure.

## Test data, logs

| Method | Used by |
|---|---|
| `testData(group, field)` | `{{tc:<group>.<field>}}` – test accounts and other data kept out of scripts |
| `listenLogs(onLog)` → stop function | `expectLog`, app errors in reports (`BistLog` with `level: 'error'`) |
| `logHistory` | `getLog` also searches logs written before the run |

`BistLog(tag, level:, time:, data:)` – `tag` is the searchable text (e.g. `POST /api/login`), `data` any Map / List /
String; `getLog(path: 'responseBody.data.userId')` walks into it (JSON strings are decoded on the way).

## Network mocking (`mockApi`, `offline`, `resetApi`)

The runner does the matching (url contains `api`, method, `times`, `delay`, offline). Your provider only translates:

```dart
@override
void attachNetwork(BistNetworkHook hook) => _hook = hook; // first mockApi / offline of a run

@override
void detachNetwork() => _hook = null; // end of the run
```

For every request your HTTP layer calls `hook(method, uri)`:

- `null` → send it for real
- `BistOffline()` → fail like a connection error
- `BistMockResponse(status, body, message: …)` → your client's response; `isError` when `status >= 400`, `message` is the
  server message found in the body (`message` / `error` / `title`)

Example for Dio:

```dart
class BistDioInterceptor extends Interceptor {
  final BistNetworkHook hook;
  BistDioInterceptor(this.hook);

  @override
  Future<void> onRequest(RequestOptions o, RequestInterceptorHandler h) async {
    final rs = await hook(o.method, o.uri);
    switch (rs) {
      case null:
        return h.next(o);
      case BistOffline():
        return h.reject(DioException.connectionError(requestOptions: o, reason: 'BIST offline'));
      case BistMockResponse(isError: false):
        return h.resolve(Response(requestOptions: o, statusCode: rs.status, data: jsonDecode(rs.body)));
      case BistMockResponse():
        final res = Response(requestOptions: o, statusCode: rs.status, data: rs.body, statusMessage: rs.message);
        return h.reject(DioException.badResponse(statusCode: rs.status, requestOptions: o, response: res));
    }
  }
}
```

Run the mock through the same response handling as real responses (token refresh, error parsing) so the app shows what
users would see.

## File picking (`pickFile`)

`addPickFile(url, name:)` downloads the file and queues it so the app's next file / image picker returns it instead of the
OS picker; `closePickFiles()` restores the real pickers and returns how many queued files were never used. The core has no
plugin dependencies, so this is up to your provider (e.g. replace `ImagePickerPlatform.instance` /
`FilePicker.platform` while files are queued).

## Custom widgets

Each method returns `null` for "not my widget" – then the built-in Material / Cupertino rules decide.

| Method | Used for |
|---|---|
| `textsOf(w)` | texts that find the widget: a button that draws an icon but has a label, an input with its own label |
| `isButton(w)` | `type: button`, finding the button around a text / icon |
| `isInput(w)` | `type: input`, the input next to a label |
| `isImage(w)` | `type: image` (e.g. `SvgPicture`) |
| `isEnabled(w)` | `expect(enabled: true)` |
| `checkedOf(w)` / `selectedOf(w)` | `expect(checked: …)` / `expect(selected: …)` |
| `isDropdown(w)` | `input(value)` taps it, then the item with that text |
| `enterText(field, value)` | `input` into a field that needs special handling – return a Future (error or `null`) |
| `inputDate(field, text, date, end:)` | `inputDate` / `inputDateRange` into your date fields |
