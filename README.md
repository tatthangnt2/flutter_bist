# flutter_bist

**Built-in self-test for Flutter apps.** Test scripts that run *inside* your app – on a real phone, in a release build, in
front of a tester – and drive the UI like a finger: tap, type, scroll, check what's on screen, fake API errors, ask the
tester to confirm what only a human can judge.

- **Runs anywhere the app runs.** No `flutter_driver`, no test harness, no computer attached. Ship the scripts with a
  tester build; testers (or an AI agent reading the console) run them from a floating panel.
- **Real input.** Touches go through `GestureBinding.handlePointerEvent`, text through the keyboard path, so covered buttons,
  disabled buttons, input formatters and validation behave exactly as for users.
- **Scripts are data.** A script is JSON (`.bist`), not code – the app never runs downloaded code. Write it in the
  **BIST Editor** (one HTML file, double-click to open), in TypeScript / JavaScript, or in Dart.
- **Works with any app, extends to any library.** The default `BistProvider` works with plain Flutter
  (`Navigator`, Material / Cupertino widgets). Override a few methods to plug in your router, HTTP client, logs, servers or
  custom widgets.

| | flutter_test / integration_test | flutter_bist |
|---|---|---|
| Where it runs | Your computer / CI, debug or profile build | Inside the app, any build, any device |
| Who runs it | Developers, CI | Developers, testers, AI agents |
| Script | Dart code compiled into the test | JSON data loaded at run time |
| Real backend data | Usually mocked | Real server (writes refused on production), or `mockApi` |
| Human checks | – | `confirm` / `ask` dialogs |

## Install

```yaml
dependencies:
  flutter_bist:
    git:
      url: https://github.com/tatthangnt2/flutter_bist.git
      ref: main
```

## Quick start

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bist/flutter_bist.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // default BistProvider (plain Flutter app); loads assets/bist/*.bist / *.json;
  // runs `flutter run --dart-define=BIST_RUN_IDS=<id>` scripts once the app is ready (dartDefine: false to turn off)
  await Bist.init(scriptAssets: 'assets/bist/');
  runApp(MaterialApp(
    navigatorObservers: [Bist.navigatorObserver], // routes for nav / back / route:
    builder: BistView.overlay, // floating "BIST" button → scripts and results (debug / profile builds)
    routes: {...},
  ));
}
```

Add the scripts to your assets (`flutter: assets: [assets/bist/]`), run the app, tap **BIST**, then **▶** on a script.
See [`example/`](example) – a login screen and an order list with a script that tests them
(`cd example && flutter test` runs it).

## Writing scripts

A script is a tree: **`BistSuite`** (children are independent; `pre` / `after` run around each child),
**`BistSequence`** (children run in order and stop at the first failure), **`BistCase`** (one test: a list of steps).

```ts
import { BistSuite, BistCase, WidgetType, expect, input, tap, tc, printJson } from 'flutter_bist';

const login = (user: string, pass: string) => [
  input(user, { text: 'Username' }),
  input(pass, { text: 'Password' }),
  tap({ text: 'SIGN IN', type: WidgetType.button }),
];

printJson(BistSuite({ id: 'login', name: 'Login', units: [
  BistCase({ name: 'Missing fields', steps: [...login('', ''), expect({ text: 'Please enter your username and password.' })] }),
  BistCase({ id: 'login.admin', name: 'Admin', steps: [...login(tc('Admin', 'userName'), tc('Admin', 'password')), expect({ route: '/home', timeout: 15000 })] }),
] }));
```

Three ways to write them – all produce the same JSON (`schema: 4`):

1. **BIST Editor** – [`bin/editor.html`](bin/editor.html). Download it, double-click (Chrome / Edge). Tree of suites and tests
   on the left, steps in the middle (completion, signatures, errors from the TypeScript language service), properties on
   the right, find / replace, find in project, undo / redo, and an optional AI assistant (Gemini, OpenRouter, Claude,
   ChatGPT, Ollama, any OpenAI-compatible server, or WebLLM in the browser). Saves a `.bist` file: minified JSON the app loads.
2. **TypeScript / JavaScript files** – `node bin/bist.mjs <scripts dir> <JSON dir>` type-checks every `<id>.ts`, runs it and
   writes `<id>.json` (needs `npm install` in `tools/editor` once, for the `typescript` package). VS Code completion works
   out of the box (a `tsconfig.json` pointing at `bin/bist.d.ts` is created).
3. **Dart** – `import 'package:flutter_bist/flutter_bist.dart';` has the same builders (in a test file: `hide expect`, it clashes with flutter_test); `script.printJson()` prints the JSON.

Finding widgets: `text` (visible text, input label / hint, tooltip, semantics label), `id` (`ValueKey`), `type`
(`button`, `input`, `text`, `image`), `icon` (Material icon name), `route`, `inside` (a card / row containing some text),
`match` (`exact`, `contains`, `regex`). A widget must match **all** given properties; BIST waits, scrolls and closes the
keyboard while looking for it. Full list of commands: [docs/commands.md](docs/commands.md).

## Connecting your app: `BistProvider`

One class, every method has a default. Override only what you need:

```dart
class MyBistProvider extends BistProvider {
  @override
  String? get currentRoute => router.location; // go_router, beamer, …

  @override
  Future<void> go(String path) async => router.go(path);

  @override
  bool get isProduction => Env.server == Server.production; // scripts with `writes: true` refuse to run

  @override
  String? testData(String group, String field) => testAccounts[group]?[field]; // {{tc:Admin.password}}

  @override
  void attachNetwork(BistNetworkHook hook) => dio.interceptors.insert(0, BistDioInterceptor(hook)); // mockApi / offline (interceptor: docs/provider.md)

  @override
  List<String?>? textsOf(Widget w) => w is MyButton ? [w.label] : null; // custom widgets
}

await Bist.init(provider: MyBistProvider(), scriptAssets: 'assets/bist/');
```

What each group of methods enables, and how to write a network adapter: [docs/provider.md](docs/provider.md).

## Results

- **Panel**: one row per run, the result tree (`BistResult`: one tree per run, shaped like the script – status, time,
  error per test); tap a test for its folder and logs.
- **Console**: every step prints a `BIST|{...}` JSON line – `adb logcat -d | grep "BIST|"` or the `flutter run` output –
  so an AI agent can run a script with `--dart-define=BIST_RUN_IDS=<id>` and read the result without a screenshot.
- **Result folder** of each run: `BistProvider.tempDir()/bist/<yyyy-MM-dd HH-mm-ss>/`, one folder per test
  (`<number>/`, e.g. `1.1.1/`) with `pre.log` / `step.log` / `after.log` (one line per action: `<step> ✓|✗ <command>`, then
  the error, app error logs and screen texts of a failed one), `error.log` (only the error) and JPEG screenshots
  `shot_<pre | step | after>_<step>.jpg` (failed steps, and steps with `shot: true`). A suite's `pre` / `after` actions
  go to the logs of the next / last test, as `<suite number>_<n>`. The `BIST|` line of each test and run gives the
  folder (`dir`).

## Limits

BIST controls what Flutter draws. OS dialogs (permissions, pickers – except files queued with `pickFile`), WebViews,
maps, camera previews and other platform views can't be driven. It doesn't replace unit tests; it covers the end-to-end
flows testers repeat on every build.

## Repository

| Path | |
|---|---|
| `lib/flutter_bist.dart` | The only public library: everything below is exported from it |
| `lib/src/unit.dart` | Script tree: `BistUnit` / `BistCase` / `BistSuite` / `BistSequence`, validation |
| `lib/src/action.dart` | Script actions: `BistAction`, the `<Command>BistAction` classes and the command names (`tap`, `input`, …) – part of `unit.dart` |
| `lib/flutter_bist.dart` | `Bist` (runner), `BistProvider`, `BistTouch`, `BistResult` |
| `lib/src/bist_view.dart` | `BistView`, `BistView.overlay`, `BistView.units` / `BistView.results` |
| `icon/logo.svg`, `icon/icon.svg` | BIST logo (680 × 304) and icon (128 × 128); `BistLogo` / `BistIcon` draw the same in Flutter |
| `lib/src/localizations.dart` | `BistLocalizations` (texts of `BistView`), `BistLocalizationsDelegate` |
| `tools/editor/` | Sources of the editor and the TS library: `editor.html`, `bist.ts`. `npm run build` writes `bin/` |
| `bin/` | Built editor (`editor.html`), command line (`bist.mjs`), types (`bist.d.ts`) – committed, CI checks they match the sources |
| `example/` | Demo app and script |

## License

MIT – see [LICENSE](LICENSE).
