part of 'unit.dart';

// Script actions: [BistAction] (one step of a script – its JSON and parameters), then the built-in commands. Each command
// is a subclass of [BistAction] (`<Command>BistAction`; Dart 3 super parameters forward the shared parameters to the
// `BistAction` constructor) and the command name is its constructor tear-off (`final tap = TapBistAction.new;`).

/// One action (step) of a script: command [cmd] and its parameters, as in the JSON.
///
/// The built-in commands are the subclasses below (`<Command>BistAction`), created through [tap], [input], …
/// [BistAction.custom] builds an action from raw JSON without validation – for custom actions (the validator and the runner
/// only know the built-in commands for now).
class BistAction {
  /// Command name, e.g. `tap`, `input`, `expect`
  final String cmd;
  final Map<String, Object?> _json;

  /// Custom action [cmd] with parameters [json] (raw JSON of the step; a `cmd` key in it is ignored). Not validated.
  BistAction.custom(this.cmd, [Map<String, Object?> json = const {}])
    : _json = Map.unmodifiable({
        'cmd': cmd,
        for (final e in json.entries)
          if (e.key != 'cmd') e.key: e.value,
      });

  /// Action [cmd] of the built-in commands, used by the command classes ([TapBistAction], [InputBistAction], …) through
  /// Dart 3 super parameters (`TapBistAction({super.text, …}) : super('tap')`). Command-specific parameters go in [args]
  /// (first in the JSON). Drops `null` and default `false`, validates and throws [ArgumentError] when invalid.
  BistAction(
    String cmd, {
    Map<String, Object?> args = const {},
    String? text,
    String? id,
    WidgetType? type,
    String? icon,
    String? route,
    String? inside,
    TextMatch? match,
    bool enabled = false,
    String? value,
    bool? focused,
    bool? obscured,
    int? maxLength,
    int? count,
    bool? checked,
    bool? selected,
    int? timeout,
    String? note,
    bool shot = false,
    List<BistAction>? onError,
  }) : this.custom(
         cmd,
         _prepare(cmd, {
           ...args,
           for (final e in {
             ..._find(text, id, type, icon, route, inside, match),
             ..._state(enabled, value, focused, obscured, maxLength, count, checked, selected),
             ..._o(timeout, note, shot, onError),
           }.entries)
             if (e.value != null && !args.containsKey(e.key)) e.key: e.value,
         }),
       );

  static Map<String, Object?> _prepare(String cmd, Map<String, Object?> args) {
    final json = <String, Object?>{'cmd': cmd};
    args.forEach((k, v) {
      if (v == null || (v == false && (k == 'enabled' || k == 'shot'))) return;
      json[k] = switch (v) {
        Enum() => v.name,
        List<BistAction>() => v.map((e) => e.toJson()).toList(),
        BistAction() => v.toJson(),
        _ => v,
      };
    });
    final errors = <String>[];
    _validateStep(json, cmd, false, null, errors);
    if (errors.isNotEmpty) throw ArgumentError(errors.join('\n'));
    return json;
  }

  /// Reads a step from JSON. Throws [FormatException] when it is invalid.
  factory BistAction.fromJson(Map<String, Object?> json) {
    final errors = <String>[];
    _validateStep(json, 'Step', false, null, errors);
    if (errors.isNotEmpty) throw FormatException(errors.join('\n'));
    return BistAction.custom(json['cmd'] as String, json);
  }

  /// Raw JSON value of parameter [key]
  Object? operator [](String key) => _json[key];

  // ==== Finding widgets (every finding command; the widget must match all of them) ====

  /// Visible text, input label / hint, tooltip or Semantics label (compared by [match])
  String? get text => _json['text'] as String?;

  /// `Key` of the widget (`ValueKey('login.submit')`)
  String? get id => _json['id'] as String?;

  /// Kind of widget (button, input, checkbox, …)
  WidgetType? get type => WidgetType.values.where((e) => e.name == _json['type']).firstOrNull;

  /// Material icon name of an icon-only button (`add`, `logout`, …)
  String? get icon => _json['icon'] as String?;

  /// Only search in the screen with this route; alone in `expect` / `notExpect`: wait until that screen is (not) open
  String? get route => _json['route'] as String?;

  /// Only search inside the block (card, list row, dialog) that contains this text
  String? get inside => _json['inside'] as String?;

  /// How [text] / [value] are compared: exact (default), contains, regex
  TextMatch get match => TextMatch.values.where((e) => e.name == _json['match']).firstOrNull ?? TextMatch.exact;

  /// Has any widget-finding property (besides [route])
  bool get hasTarget => text != null || id != null || icon != null || type != null;

  // ==== Conditions of expect / notExpect ====

  /// The button / input is enabled
  bool get enabled => _json['enabled'] == true;

  /// `expect` / `notExpect`: current text of the input (after the app's formatters); `null` = not checked.
  /// For `input` / `inputDate` the value to type is [value].
  String? get fieldValue => cmd == 'expect' || cmd == 'notExpect' ? _json['value'] as String? : null;

  /// The input has focus
  bool? get focused => _json['focused'] as bool?;

  /// The input hides its characters (password)
  bool? get obscured => _json['obscured'] as bool?;

  /// Maximum length of the input
  int? get maxLength => (_json['maxLength'] as num?)?.toInt();

  /// Number of matching widgets
  int? get count => (_json['count'] as num?)?.toInt();

  /// Checkbox / switch / radio is checked
  bool? get checked => _json['checked'] as bool?;

  /// Tab / chip / list item is selected
  bool? get selected => _json['selected'] as bool?;

  // ==== Command parameters ====

  /// `input` / `inputDate`: text or date to enter (`expect`: see [fieldValue])
  String? get value => _json['value'] as String?;

  /// `inputDateRange`: first day (`dd/MM/yyyy`)
  String? get start => _json['start'] as String?;

  /// `inputDateRange`: last day (`dd/MM/yyyy`)
  String? get end => _json['end'] as String?;

  /// `pickFile`: https URL of the sample file
  String? get url => _json['url'] as String?;

  /// `swipe`: finger direction
  SwipeDirection? get direction => SwipeDirection.values.where((e) => e.name == _json['direction']).firstOrNull;

  /// `wait`: milliseconds to wait
  int? get ms => (_json['ms'] as num?)?.toInt();

  /// `runTest`: id of the node to run
  String? get script => _json['script'] as String?;

  /// `nav`: route to open; `getLog`: path in the log data (see [dataPath])
  String? get path => _json['path'] as String?;

  /// `getLog`: dotted path in the log data, e.g. `responseBody.data.userId`
  String? get dataPath => _json['path'] as String?;

  /// Variable name (`randInt`, `randText`, `getText`, `getLog`, `getEnv`, `ask`); `server`: server name; `pickFile`: file name
  String? get name => _json['name'] as String?;

  /// `getEnv`: environment key, e.g. `user.name`, `app.version`
  String? get key => _json['key'] as String?;

  /// `getLog` / `expectLog`: text contained in the log tag
  String? get tag => _json['tag'] as String?;

  /// `getLog` / `expectLog`: log level
  LogLevel? get level => LogLevel.values.where((e) => e.name == _json['level']).firstOrNull;

  /// `mockApi`: text contained in the request URL
  String? get api => _json['api'] as String?;

  /// `mockApi`: HTTP status of the fake response (default 200)
  int? get status => (_json['status'] as num?)?.toInt();

  /// `mockApi`: body of the fake response (JSON text)
  String? get body => _json['body'] as String?;

  /// `mockApi`: delay before the fake response (ms)
  int? get delay => (_json['delay'] as num?)?.toInt();

  /// `mockApi`: number of uses before the mock is removed (default: until the run ends)
  int? get times => (_json['times'] as num?)?.toInt();

  /// `mockApi`: only requests with this HTTP method
  String? get method => _json['method'] as String?;

  /// `offline`: true = no network, false = network back
  bool get on => _json['on'] != false;

  /// `loop`: first value of `{{i}}`
  int? get from => (_json['from'] as num?)?.toInt();

  /// `loop`: last value of `{{i}}`
  int? get to => (_json['to'] as num?)?.toInt();

  /// `randInt`: smallest number
  int? get min => (_json['min'] as num?)?.toInt();

  /// `randInt`: largest number; `loopWhile`: maximum iterations
  int? get max => (_json['max'] as num?)?.toInt();

  /// `randText`: shortest length (longest: [maxLength])
  int? get minLength => (_json['minLength'] as num?)?.toInt();

  /// `randText`: characters to pick from
  String? get chars => _json['chars'] as String?;

  /// `randInt` / `randText`: text containing `{value}`, e.g. `'Order {value}'`
  String? get format => _json['format'] as String?;

  /// `loop` / `loopWhile`: actions of one iteration
  List<BistAction> get steps => _actions(_json['steps']);

  /// `loopWhile`: condition (`expect` / `notExpect`) checked before each iteration
  BistAction? get condition => _json['condition'] is Map ? BistAction._fromMap(_json['condition'] as Map) : null;

  /// `log` / `toast` / `confirm` / `ask`: message
  String? get message => _json['message'] as String?;

  /// `confirm`: text of the passing button (default "Yes")
  String? get yes => _json['yes'] as String?;

  /// `confirm`: text of the failing button (default "No")
  String? get no => _json['no'] as String?;

  /// `ask`: prefilled text
  String? get initial => _json['initial'] as String?;

  /// `ask`: hint text
  String? get hint => _json['hint'] as String?;

  // ==== Shared parameters ====

  /// How long to wait for a widget / condition (ms, default 5000)
  int? get timeout => (_json['timeout'] as num?)?.toInt();

  /// Note shown in the results
  String? get note => _json['note'] as String?;

  /// Take a screenshot at this step (a failing step always does)
  bool get shot => _json['shot'] == true;

  /// Actions run when this step fails; if they all pass the script goes on (one level only)
  List<BistAction> get onError => _actions(_json['onError']);

  static BistAction _fromMap(Map m) => BistAction.custom(m['cmd'] as String, Map<String, Object?>.from(m));

  static List<BistAction> _actions(Object? list) => ((list as List?) ?? const []).map((e) => _fromMap(e as Map)).toList();

  /// JSON of the step (sent to the app)
  Map<String, Object?> toJson() => Map.of(_json);

  /// One readable line, e.g. `tap text "Send" type button`, `input = "abc" text "Username"`
  String describe() {
    final f = _fields[cmd]!;
    if (cmd == 'loop') return 'loop {{i}} = $from..$to (${steps.length} actions)';
    if (cmd == 'loopWhile') return 'loopWhile ${condition?.describe()} (${steps.length} actions, at most ${max ?? kLoopWhileMax} iterations)';
    if (cmd == 'log' || cmd == 'toast' || cmd == 'confirm') return '$cmd "$message"';
    if (cmd == 'ask') return 'ask {{$name}} ← "$message"';
    if (cmd == 'getText')
      return 'getText {{$name}} ← ${[for (final k in kFindKeys)
        if (_json[k] != null) '$k "${_json[k]}"'].join(' ')}';
    if (cmd == 'getLog') return 'getLog {{$name}} ← log "$tag"${dataPath == null ? '' : ' $dataPath'}${level == null ? '' : ' (${level!.name})'}';
    if (cmd == 'getEnv') return 'getEnv {{$name}} ← $key';
    if (cmd == 'mockApi')
      return 'mockApi ${method ?? ''}${method == null ? '' : ' '}"$api" → ${status ?? 200}${delay == null ? '' : ' after ${delay}ms'}${times == null ? '' : ' ($times times)'}';
    if (cmd == 'offline') return on ? 'offline (no network)' : 'offline off (network back)';
    if (cmd == 'pickFile') return 'pickFile $url${name == null ? '' : ' → "$name"'}';
    if (cmd == 'randInt') return 'randInt {{$name}} = $min..$max${format == null ? '' : ' "$format"'}';
    if (cmd == 'randText') return 'randText {{$name}} length $minLength..${_json['maxLength']}${format == null ? '' : ' "$format"'}';
    return [
      cmd,
      for (final k in f.main) k == 'value' && cmd != 'expect' ? '= "${_json[k]}"' : '${_json[k]}',
      for (final k in [...kFindKeys, ...f.extra])
        if (_json[k] != null) _json[k] is String ? '$k "${_json[k]}"' : '$k ${_json[k]}',
    ].join(' ');
  }

  @override
  String toString() => jsonEncode(_json);
}

// ==== Tap, input ====

/// Taps the widget matching every property given
class TapBistAction extends BistAction {
  TapBistAction({super.text, super.id, super.type, super.icon, super.route, super.inside, super.match, super.timeout, super.note, super.shot, super.onError})
    : super('tap');
}

/// Command `tap` – see [TapBistAction].
final tap = TapBistAction.new;

/// Long press (700 ms)
class TapLongBistAction extends BistAction {
  TapLongBistAction({
    super.text,
    super.id,
    super.type,
    super.icon,
    super.route,
    super.inside,
    super.match,
    super.timeout,
    super.note,
    super.shot,
    super.onError,
  }) : super('tapLong');
}

/// Command `tapLong` – see [TapLongBistAction].
final tapLong = TapLongBistAction.new;

/// Double tap
class TapDoubleBistAction extends BistAction {
  TapDoubleBistAction({
    super.text,
    super.id,
    super.type,
    super.icon,
    super.route,
    super.inside,
    super.match,
    super.timeout,
    super.note,
    super.shot,
    super.onError,
  }) : super('tapDouble');
}

/// Command `tapDouble` – see [TapDoubleBistAction].
final tapDouble = TapDoubleBistAction.new;

/// Types [value] into an input (replaces the old text; `''` clears it). `text` is the input's label / hint, or the text right
/// above / before the input. Without any finding property it types into the focused input. Dropdowns: picks the item [value].
class InputBistAction extends BistAction {
  InputBistAction(
    String value, {
    super.text,
    super.id,
    super.type,
    super.icon,
    super.route,
    super.inside,
    super.match,
    super.timeout,
    super.note,
    super.shot,
    super.onError,
  }) : super('input', args: {'value': value});
}

/// Command `input` – see [InputBistAction].
final input = InputBistAction.new;

/// Picks a date in a date field ([value] as `dd/MM/yyyy`, or `{{date:+1}}`)
class InputDateBistAction extends BistAction {
  InputDateBistAction(
    String value, {
    super.text,
    super.id,
    super.type,
    super.icon,
    super.route,
    super.inside,
    super.match,
    super.timeout,
    super.note,
    super.shot,
    super.onError,
  }) : super('inputDate', args: {'value': value});
}

/// Command `inputDate` – see [InputDateBistAction].
final inputDate = InputDateBistAction.new;

/// Picks a date range ([start] to [end], `dd/MM/yyyy`) in a date range field
class InputDateRangeBistAction extends BistAction {
  InputDateRangeBistAction(
    String start,
    String end, {
    super.text,
    super.id,
    super.type,
    super.icon,
    super.route,
    super.inside,
    super.match,
    super.timeout,
    super.note,
    super.shot,
    super.onError,
  }) : super('inputDateRange', args: {'start': start, 'end': end});
}

/// Command `inputDateRange` – see [InputDateRangeBistAction].
final inputDateRange = InputDateRangeBistAction.new;

/// Sample file for file / image pickers: downloads [url] (https, cached) when the step runs; the app's next file / image /
/// video picker returns this file instead of the OS picker (call several times → pick several files). [name]: file name the
/// app sees (default: last path segment). Put it before the step that taps the "choose file" button.
class PickFileBistAction extends BistAction {
  PickFileBistAction(String url, {String? name, super.note}) : super('pickFile', args: {'url': url, 'name': name});
}

/// Command `pickFile` – see [PickFileBistAction].
final pickFile = PickFileBistAction.new;

// ==== Checks ====

/// Waits until a widget matching every property is shown (scrolls to find it). Only `route` = waits until that screen is open.
/// Extra conditions: [enabled] button / input is enabled; for inputs: [value] current text (after the app's formatters),
/// [focused], [obscured] (password), [maxLength]; [count] number of matching widgets; [checked] checkbox / switch / radio;
/// [selected] tab / chip / list item. Error under an input: `expect(text: '<error text>')`.
class ExpectBistAction extends BistAction {
  ExpectBistAction({
    super.text,
    super.id,
    super.type,
    super.icon,
    super.route,
    super.inside,
    super.match,
    super.enabled,
    super.value,
    super.focused,
    super.obscured,
    super.maxLength,
    super.count,
    super.checked,
    super.selected,
    super.timeout,
    super.note,
    super.shot,
    super.onError,
  }) : super('expect');
}

/// Command `expect` – see [ExpectBistAction].
final expect = ExpectBistAction.new;

/// Waits until the widget is gone (e.g. "Loading" disappears). Only `route` = waits until that screen is left.
/// With extra conditions ([value], [focused], …) it passes when the widget does **not** meet them.
class NotExpectBistAction extends BistAction {
  NotExpectBistAction({
    super.text,
    super.id,
    super.type,
    super.icon,
    super.route,
    super.inside,
    super.match,
    super.enabled,
    super.value,
    super.focused,
    super.obscured,
    super.maxLength,
    super.count,
    super.checked,
    super.selected,
    super.timeout,
    super.note,
    super.shot,
    super.onError,
  }) : super('notExpect');
}

/// Command `notExpect` – see [NotExpectBistAction].
final notExpect = NotExpectBistAction.new;

// ==== Navigation, scrolling, waiting ====

/// Goes back (closes the top dialog / screen), like Android's Back button
class BackBistAction extends BistAction {
  BackBistAction({super.note, super.shot, super.onError}) : super('back');
}

/// Command `back` – see [BackBistAction].
final back = BackBistAction.new;

/// Swipes a finger in [direction]: `up` = see what's below, `down` = pull down (pull-to-refresh at the top of a list).
/// With finding properties it swipes inside the scrollable containing that widget, otherwise the largest scrollable.
class SwipeBistAction extends BistAction {
  SwipeBistAction(
    SwipeDirection direction, {
    super.text,
    super.id,
    super.type,
    super.icon,
    super.route,
    super.inside,
    super.match,
    super.note,
    super.shot,
    super.onError,
  }) : super('swipe', args: {'direction': direction});
}

/// Command `swipe` – see [SwipeBistAction].
final swipe = SwipeBistAction.new;

/// Waits exactly [ms] milliseconds – only when there is nothing to `expect` / `notExpect`
class WaitBistAction extends BistAction {
  WaitBistAction(int ms, {super.note, super.shot}) : super('wait', args: {'ms': ms});
}

/// Command `wait` – see [WaitBistAction].
final wait = WaitBistAction.new;

/// Runs the script / node [script] (an id, e.g. login) then continues
class RunTestBistAction extends BistAction {
  RunTestBistAction(String script, {super.note, super.onError}) : super('runTest', args: {'script': script});
}

/// Command `runTest` – see [RunTestBistAction].
final runTest = RunTestBistAction.new;

// ==== For developers ====

/// Opens the screen with route [path] directly, like a deep link (good for preconditions)
class NavBistAction extends BistAction {
  NavBistAction(String path, {super.timeout, super.note, super.shot, super.onError}) : super('nav', args: {'path': path});
}

/// Command `nav` – see [NavBistAction].
final nav = NavBistAction.new;

/// Switches the app to server [name] (needs a `BistProvider` that supports servers)
class ServerBistAction extends BistAction {
  ServerBistAction(String name, {super.timeout, super.note, super.onError}) : super('server', args: {'name': name});
}

/// Command `server` – see [ServerBistAction].
final server = ServerBistAction.new;

/// Waits for a new app log (since the previous step started) whose `tag` contains [tag], with [level] if given
class ExpectLogBistAction extends BistAction {
  ExpectLogBistAction(String tag, {LogLevel? level, super.timeout, super.note, super.onError}) : super('expectLog', args: {'tag': tag, 'level': level});
}

/// Command `expectLog` – see [ExpectLogBistAction].
final expectLog = ExpectLogBistAction.new;

// ==== Fake server (removed automatically when the run ends) ====

/// Requests whose URL contains [api] (and [method], if given) get a fake response: status [status] (default 200), body
/// [body] (JSON text), after [delay] ms; removed after [times] uses (default: until the run ends). For error screens, empty
/// data, slow network. Needs a `BistProvider` that supports network mocking.
class MockApiBistAction extends BistAction {
  MockApiBistAction(String api, {int? status, String? body, int? delay, int? times, String? method, super.note})
    : super('mockApi', args: {'api': api, 'status': status, 'body': body, 'delay': delay, 'times': times, 'method': method});
}

/// Command `mockApi` – see [MockApiBistAction].
final mockApi = MockApiBistAction.new;

/// Simulates no network ([on] = true) or network back (false): every request fails like when offline
class OfflineBistAction extends BistAction {
  OfflineBistAction({bool on = true, super.note}) : super('offline', args: {'on': on});
}

/// Command `offline` – see [OfflineBistAction].
final offline = OfflineBistAction.new;

/// Removes every [mockApi] / [offline]
class ResetApiBistAction extends BistAction {
  ResetApiBistAction({super.note}) : super('resetApi');
}

/// Command `resetApi` – see [ResetApiBistAction].
final resetApi = ResetApiBistAction.new;

// ==== Loops, generated data ====

/// Runs [steps] with `{{i}}` = [from], [from]+1, … [to] (counts down if [from] > [to]); stops at a failing action.
/// Named `loop` because `for` is a Dart keyword.
class LoopBistAction extends BistAction {
  LoopBistAction(int from, int to, List<BistAction> steps, {super.note, super.onError}) : super('loop', args: {'from': from, 'to': to, 'steps': steps});
}

/// Command `loop` – see [LoopBistAction].
final loop = LoopBistAction.new;

/// Loop: checks [condition] (an `expect(...)` / `notExpect(...)`, use a short `timeout`); true → runs [steps]; false → stops
/// (passed). Still true after [max] iterations → fails. Named `loopWhile` because `while` is a Dart keyword.
class LoopWhileBistAction extends BistAction {
  LoopWhileBistAction(BistAction condition, List<BistAction> steps, {int? max, super.note, super.onError})
    : super('loopWhile', args: {'condition': condition, 'steps': steps, 'max': max});
}

/// Command `loopWhile` – see [LoopWhileBistAction].
final loopWhile = LoopWhileBistAction.new;

/// Random number in [min]..[max] saved to `{{name}}`. [format]: text with `{value}`, e.g. `'Order {value}'`
/// (don't write `$value` – Dart would replace it while writing).
class RandIntBistAction extends BistAction {
  RandIntBistAction(String name, int min, int max, {String? format, super.note})
    : super('randInt', args: {'name': name, 'min': min, 'max': max, 'format': format});
}

/// Command `randInt` – see [RandIntBistAction].
final randInt = RandIntBistAction.new;

/// Random text of [minLength]..[maxLength] characters from [chars] (default lowercase + digits) saved to `{{name}}`.
/// [format]: text with `{value}`, e.g. `'BIST-{value}'`.
class RandTextBistAction extends BistAction {
  RandTextBistAction(String name, int minLength, int maxLength, {String? chars, String? format, super.note})
    : super('randText', args: {'name': name, 'minLength': minLength, 'maxLength': maxLength, 'chars': chars, 'format': format});
}

/// Command `randText` – see [RandTextBistAction].
final randText = RandTextBistAction.new;

// ==== Read values into variables ====

/// Saves the text of the found widget to `{{name}}`: text on screen (`Text`), or the current text of an input.
/// E.g. `getText('fullName', text: 'Full name', type: WidgetType.input)`.
class GetTextBistAction extends BistAction {
  GetTextBistAction(
    String name, {
    super.text,
    super.id,
    super.type,
    super.icon,
    super.route,
    super.inside,
    super.match,
    super.timeout,
    super.note,
    super.onError,
  }) : super('getText', args: {'name': name});
}

/// Command `getText` – see [GetTextBistAction].
final getText = GetTextBistAction.new;

/// Saves a value from the newest app log whose tag contains [tag] (with [level], if given) to `{{name}}`. [path]: dotted path
/// in the log data, numbers are list positions – e.g. for an API log `POST /api/login`:
/// `getLog('userId', 'login', path: 'responseBody.data.userId')`. Waits up to [timeout] if there is no log yet.
class GetLogBistAction extends BistAction {
  GetLogBistAction(String name, String tag, {String? path, LogLevel? level, super.timeout, super.note, super.onError})
    : super('getLog', args: {'name': name, 'tag': tag, 'path': path, 'level': level});
}

/// Command `getLog` – see [GetLogBistAction].
final getLog = GetLogBistAction.new;

/// Saves environment value [key] to `{{name}}` (or use `{{env:<key>}}` directly, see [env]). Built-in keys: `route`,
/// `app.version`, `server.name`; others come from the app (`Bist.values['<key>']`, `BistProvider.env`), e.g. `user.name`.
/// Secret-looking keys (token, password…) are refused.
class GetEnvBistAction extends BistAction {
  GetEnvBistAction(String name, String key, {super.note, super.onError}) : super('getEnv', args: {'name': name, 'key': key});
}

/// Command `getEnv` – see [GetEnvBistAction].
final getEnv = GetEnvBistAction.new;

// ==== Print, notify, ask the tester ====

/// Writes [message] to the step log and the `BIST|` log (variables allowed, e.g. `log('userId = {{uid}}')`).
/// Named `log` because `print` is a built-in Dart function.
class LogBistAction extends BistAction {
  LogBistAction(String message, {super.note}) : super('log', args: {'message': message});
}

/// Command `log` – see [LogBistAction].
final log = LogBistAction.new;

/// Shows a short message on screen, doesn't wait
class ToastBistAction extends BistAction {
  ToastBistAction(String message, {super.note}) : super('toast', args: {'message': message});
}

/// Command `toast` – see [ToastBistAction].
final toast = ToastBistAction.new;

/// Dialog asking the tester [message] (e.g. "Is the button color right?"): [yes] (default "Yes") passes, [no] (default
/// "No") fails. No answer after [timeout] (default 5 minutes) fails – don't use it in unattended runs.
class ConfirmBistAction extends BistAction {
  ConfirmBistAction(String message, {String? yes, String? no, super.timeout, super.note, super.onError})
    : super('confirm', args: {'message': message, 'yes': yes, 'no': no});
}

/// Command `confirm` – see [ConfirmBistAction].
final confirm = ConfirmBistAction.new;

/// Dialog for the tester to type a value (e.g. an OTP sent to their phone), saved to `{{name}}`. [initial]: prefilled text,
/// [hint]: hint text. Cancel or no answer after [timeout] (default 5 minutes) fails.
class AskBistAction extends BistAction {
  AskBistAction(String name, String message, {String? initial, String? hint, super.timeout, super.note, super.onError})
    : super('ask', args: {'name': name, 'message': message, 'initial': initial, 'hint': hint});
}

/// Command `ask` – see [AskBistAction].
final ask = AskBistAction.new;
