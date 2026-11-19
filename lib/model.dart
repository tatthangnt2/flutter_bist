/// BIST script model – pure Dart (no Flutter import), so scripts can also be written in Dart and printed with `dart run`.
///
/// A script is a tree: [TestGroup] (children are independent) / [TestSequence] (children run in order) containing
/// [TestUnit]s (one test with a list of [TestAction]s) or sub-groups. Every node is a [TestCase] with an optional `id`,
/// `pre` / `after` (preconditions / cleanup), `writes`, `manual` and `minVersion` / `maxVersion` (`1.0.0+10`).
/// One script file = one root [TestGroup]. The in-app runner (`package:flutter_bist/flutter_bist.dart`) reads the same JSON
/// back with these classes ([TestGroup.fromJson]).
///
/// **Finding widgets:** every command that finds a widget accepts the properties below; the widget must match **all** of
/// the properties given:
/// - `text`: text shown on screen (also input labels / hints, tooltips, Semantics labels) – exact match unless `match` says otherwise
/// - `id`: the widget `Key` (`ValueKey('login.submit')`)
/// - `type`: kind of widget [WidgetType] – `button`, `input`, `text`, `image`
/// - `icon`: name of a Material icon, for icon-only buttons (`add`, `logout`, …)
/// - `route`: only look inside the screen with this route
/// - `inside`: only look inside a block (card, list row, dialog) that contains this text
///
/// ```dart
/// import 'package:flutter_bist/model.dart';
///
/// List<TestAction> login(String user, String pass) => [
///   input(user, text: 'Username'),
///   input(pass, text: 'Password'),
///   tap(text: 'SIGN IN', type: WidgetType.button),
/// ];
///
/// final script = TestGroup(id: 'login', name: 'Login', cases: [
///   TestUnit(name: 'Missing fields', steps: [...login('', ''), expect(text: 'Please enter username and password.')]),
///   TestUnit(id: 'login.admin', name: 'Admin', steps: [
///     ...login(tc('Admin', 'userName'), tc('Admin', 'password')),
///     notExpect(text: 'SIGN IN', timeout: 15000),
///   ]),
/// ]);
///
/// void main() => script.printJson();
/// ```
library;

import 'dart:convert';

/// JSON format version. The runner skips scripts with a higher number ("needs a newer app").
const kTestScriptSchema = 4;

/// Kind of widget for the `type` property
enum WidgetType { button, input, text, image }

/// How `text` (finding widgets) and `value` (checking inputs) are compared: exact (default), contains, regular expression
enum TextMatch { exact, contains, regex }

/// HTTP methods for [mockApi]
const kHttpMethods = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'];

/// Log level for [expectLog] / [getLog]
enum LogLevel { debug, info, warn, error, damage, success }

/// Default maximum iterations of [loopWhile] (avoids endless loops)
const kLoopWhileMax = 20;

/// Finger direction of [swipe]
enum SwipeDirection { up, down, left, right }

/// Properties for finding a widget (shared by all finding commands)
const kFindKeys = ['text', 'id', 'type', 'icon', 'route', 'inside', 'match'];

const _opt = ['timeout', 'note', 'shot', 'onError'];

/// Extra conditions of `expect` / `notExpect` on the widget / input state.
/// `count`: number of matching widgets on screen; `checked`: checkbox / switch / radio; `selected`: tab / chip / selected item
const _fieldState = ['enabled', 'value', 'focused', 'obscured', 'maxLength', 'count', 'checked', 'selected'];

/// Reserved variable names (not allowed for `randInt` / `randText` / …)
const _reservedVars = ['now', 'date', 'tc', 'i'];

/// Required / optional fields of each command (besides [_opt]); `find`: the command finds a widget
const _fields = <String, ({List<String> main, List<String> extra, bool find})>{
  // tap, input
  'tap': (main: [], extra: [], find: true),
  'tapLong': (main: [], extra: [], find: true),
  'tapDouble': (main: [], extra: [], find: true),
  'input': (main: ['value'], extra: [], find: true),
  'inputDate': (main: ['value'], extra: [], find: true),
  'inputDateRange': (main: ['start', 'end'], extra: [], find: true),
  'pickFile': (main: ['url'], extra: ['name'], find: false),
  // checks
  'expect': (main: [], extra: _fieldState, find: true),
  'notExpect': (main: [], extra: _fieldState, find: true),
  // navigation, scrolling, waiting
  'back': (main: [], extra: [], find: false),
  'swipe': (main: ['direction'], extra: [], find: true),
  'wait': (main: ['ms'], extra: [], find: false),
  'runTest': (main: ['script'], extra: [], find: false),
  // loops, generated data
  'loop': (main: ['from', 'to', 'steps'], extra: [], find: false),
  'loopWhile': (main: ['condition', 'steps'], extra: ['max'], find: false),
  'randInt': (main: ['name', 'min', 'max'], extra: ['format'], find: false),
  'randText': (main: ['name', 'minLength', 'maxLength'], extra: ['chars', 'format'], find: false),
  // read values (screen, logs, environment) into variables
  'getText': (main: ['name'], extra: [], find: true),
  'getLog': (main: ['name', 'tag'], extra: ['path', 'level'], find: false),
  'getEnv': (main: ['name', 'key'], extra: [], find: false),
  // print, notify, ask the tester
  'log': (main: ['message'], extra: [], find: false),
  'toast': (main: ['message'], extra: [], find: false),
  'confirm': (main: ['message'], extra: ['yes', 'no'], find: false),
  'ask': (main: ['name', 'message'], extra: ['initial', 'hint'], find: false),
  // for developers
  'nav': (main: ['path'], extra: [], find: false),
  'server': (main: ['name'], extra: [], find: false),
  'expectLog': (main: ['tag'], extra: ['level'], find: false),
  // fake server (removed automatically when the run ends)
  'mockApi': (main: ['api'], extra: ['status', 'body', 'delay', 'times', 'method'], find: false),
  'offline': (main: [], extra: ['on'], find: false),
  'resetApi': (main: [], extra: [], find: false),
};

/// Commands of the current `schema`
final List<String> kTestCommands = List.unmodifiable(_fields.keys);

/// Placeholders replaced at run time (in every string parameter):
/// - `{{tc:<group>.<field>}}` – test data provided by the app (test accounts), see [tc]
/// - `{{now}}` – start time of the run `HHmmss`, constant for the whole run (unique text to find data created by the run)
/// - `{{date}}`, `{{date:+1}}`, `{{date:-2}}` – today ± n days, `dd/MM/yyyy`
/// - `{{i}}` – current iteration of [loop]
/// - `{{env:<key>}}` – user / app / server info (see [getEnv]), used directly without a variable
/// - `{{<name>}}` – variables created by [randInt] / [randText] / [getText] / [getLog] / [getEnv] / [ask]
final kTestValuePattern = RegExp(r'\{\{(tc:[^{}]+|env:[^{}]+|date(?::[+-]\d+)?|[A-Za-z_][A-Za-z0-9_]*)\}\}');

/// Secret-looking keys / paths – [getEnv], [getLog] and `{{env:...}}` refuse them (no tokens, passwords in reports)
final kSecretPattern = RegExp(
  r'token|password|passwd|secret|crypto|apikey|api_key|private|cookie|authorization|header|credential|mat_?khau',
  caseSensitive: false,
);

/// Test data provided by the app (`BistProvider.testData`) – keeps passwords out of scripts.
/// E.g. `input(tc('Admin', 'password'), text: 'Password')`.
String tc(String group, String field) => '{{tc:$group.$field}}';

/// Environment info used directly in text, e.g. `expect(text: env('user.name'))` (see [getEnv])
String env(String key) => '{{env:$key}}';

/// One action (step) of a script: command [cmd] and its parameters, as in the JSON
class TestAction {
  final String cmd;
  final Map<String, Object?> _json;

  TestAction._(this.cmd, Map<String, Object?> json) : _json = Map.unmodifiable(json);

  factory TestAction._build(String cmd, Map<String, Object?> args) {
    final json = <String, Object?>{'cmd': cmd};
    args.forEach((k, v) {
      if (v == null || (v == false && (k == 'enabled' || k == 'shot'))) return;
      json[k] = switch (v) {
        Enum() => v.name,
        List<TestAction>() => v.map((e) => e.toJson()).toList(),
        TestAction() => v.toJson(),
        _ => v,
      };
    });
    final errors = <String>[];
    _validateStep(json, cmd, false, null, errors);
    if (errors.isNotEmpty) throw ArgumentError(errors.join('\n'));
    return TestAction._(cmd, json);
  }

  /// Reads a step from JSON. Throws [FormatException] when it is invalid.
  factory TestAction.fromJson(Map<String, Object?> json) {
    final errors = <String>[];
    _validateStep(json, 'Step', false, null, errors);
    if (errors.isNotEmpty) throw FormatException(errors.join('\n'));
    return TestAction._(json['cmd'] as String, json);
  }

  Object? operator [](String key) => _json[key];

  // finding widgets
  String? get text => _json['text'] as String?;
  String? get id => _json['id'] as String?;
  WidgetType? get type => WidgetType.values.where((e) => e.name == _json['type']).firstOrNull;
  String? get icon => _json['icon'] as String?;
  String? get route => _json['route'] as String?;
  String? get inside => _json['inside'] as String?;

  /// Has any widget-finding property (besides `route`)
  bool get hasTarget => text != null || id != null || icon != null || type != null;
  TextMatch get match => TextMatch.values.where((e) => e.name == _json['match']).firstOrNull ?? TextMatch.exact;
  int? get count => (_json['count'] as num?)?.toInt();
  bool? get checked => _json['checked'] as bool?;
  bool? get selected => _json['selected'] as bool?;
  String? get api => _json['api'] as String?;
  int? get status => (_json['status'] as num?)?.toInt();
  String? get body => _json['body'] as String?;
  int? get delay => (_json['delay'] as num?)?.toInt();
  int? get times => (_json['times'] as num?)?.toInt();
  String? get method => _json['method'] as String?;
  bool get on => _json['on'] != false;

  String? get value => _json['value'] as String?;
  SwipeDirection? get direction => SwipeDirection.values.where((e) => e.name == _json['direction']).firstOrNull;
  String? get script => _json['script'] as String?;
  String? get path => _json['path'] as String?;
  String? get name => _json['name'] as String?;
  String? get tag => _json['tag'] as String?;
  LogLevel? get level => LogLevel.values.where((e) => e.name == _json['level']).firstOrNull;
  String? get note => _json['note'] as String?;
  bool get enabled => _json['enabled'] == true;

  /// Extra input conditions of expect / notExpect (null = not checked)
  String? get fieldValue => cmd == 'expect' || cmd == 'notExpect' ? _json['value'] as String? : null;
  bool? get focused => _json['focused'] as bool?;
  bool? get obscured => _json['obscured'] as bool?;
  int? get maxLength => (_json['maxLength'] as num?)?.toInt();

  // inputDateRange
  String? get start => _json['start'] as String?;
  String? get end => _json['end'] as String?;

  // loop / loopWhile / randInt / randText
  int? get from => (_json['from'] as num?)?.toInt();
  int? get to => (_json['to'] as num?)?.toInt();
  int? get min => (_json['min'] as num?)?.toInt();
  int? get max => (_json['max'] as num?)?.toInt();
  int? get minLength => (_json['minLength'] as num?)?.toInt();
  String? get chars => _json['chars'] as String?;
  String? get format => _json['format'] as String?;
  String? get url => _json['url'] as String?;
  String? get key => _json['key'] as String?;
  String? get message => _json['message'] as String?;
  String? get yes => _json['yes'] as String?;
  String? get no => _json['no'] as String?;
  String? get initial => _json['initial'] as String?;
  String? get hint => _json['hint'] as String?;
  String? get dataPath => _json['path'] as String?;
  List<TestAction> get steps => _actions(_json['steps']);
  TestAction? get condition => _json['condition'] is Map ? TestAction._fromMap(_json['condition'] as Map) : null;

  static TestAction _fromMap(Map m) => TestAction._(m['cmd'] as String, Map<String, Object?>.from(m));

  static List<TestAction> _actions(Object? list) => ((list as List?) ?? const []).map((e) => _fromMap(e as Map)).toList();
  bool get shot => _json['shot'] == true;
  int? get ms => (_json['ms'] as num?)?.toInt();
  int? get timeout => (_json['timeout'] as num?)?.toInt();

  List<TestAction> get onError => _actions(_json['onError']);

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

/// App version `versionName+versionCode`, e.g. `1.0.21+146` (without `+code` only versionName is compared)
class TestVersion implements Comparable<TestVersion> {
  final List<int> name;
  final int? code;

  const TestVersion(this.name, [this.code]);

  static final _pattern = RegExp(r'^(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$');

  static bool isValid(String s) => _pattern.hasMatch(s);

  /// Reads `1.0.0+10`; throws [FormatException] when invalid
  factory TestVersion.parse(String s) {
    final m = _pattern.firstMatch(s.trim());
    if (m == null) throw FormatException('Version must look like 1.0.0+10: "$s"');
    return TestVersion([int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)], m[4] == null ? null : int.parse(m[4]!));
  }

  /// Reads a version from an app's version name / code (e.g. `1.2.0-beta` + `15`), `null` if it can't
  static TestVersion? tryFrom(String? versionName, [Object? versionCode]) {
    if (versionName == null) return null;
    final name = versionName.split(RegExp(r'[^0-9.]')).first;
    try {
      return TestVersion.parse(versionCode == null ? name : '$name+$versionCode');
    } on FormatException {
      return null;
    }
  }

  @override
  int compareTo(TestVersion o) {
    for (var i = 0; i < 3; i++) {
      final c = name[i].compareTo(o.name[i]);
      if (c != 0) return c;
    }
    if (code == null || o.code == null) return 0;
    return code!.compareTo(o.code!);
  }

  @override
  String toString() => '${name.join('.')}${code == null ? '' : '+$code'}';
}

/// A node of the script tree: [TestUnit], [TestGroup], [TestSequence]
abstract class TestCase {
  final String name;

  /// For calling it again (`runTest(id)`) and running it alone (`--dart-define=BIST_RUN_IDS=<id>`); unique in the whole tree
  final String? id;

  /// Only runs when the app version is within [minVersion]..[maxVersion] (inclusive, `1.0.0+10`); otherwise "Not applicable"
  final String? minVersion, maxVersion;

  /// A case that can't be automated (the reason): still shown in the tree, reported as "Needs a tester", not a failure
  final String? manual;

  /// Creates / changes data: only runs on non-production servers. Set on a group, every child counts as writing.
  final bool writes;

  /// Preconditions (best written as "check first, act only if missing") and cleanup (runs even after a failure).
  /// On a [TestGroup]: before / after **each** child; on a [TestSequence]: once before / after the whole sequence.
  final List<TestAction> pre, after;

  TestGroup? _parent;

  TestCase._(this.name, this.id, this.minVersion, this.maxVersion, this.manual, this.writes, List<TestAction>? pre, List<TestAction>? after)
    : pre = List.unmodifiable(pre ?? const []),
      after = List.unmodifiable(after ?? const []);

  TestGroup? get parent => _parent;

  /// From the root to this node
  List<TestCase> get path => [...?_parent?.path, this];

  /// Number by position, e.g. `2.1.3` (the root has no number)
  String get number {
    final p = _parent;
    if (p == null) return '';
    final n = '${p.cases.indexOf(this) + 1}';
    return p.number.isEmpty ? n : '${p.number}.$n';
  }

  /// [writes] of this node or a parent group
  bool get isWrites => writes || (_parent?.isWrites ?? false);

  /// Whether [version] is within the version range of this node and every parent
  bool appliesTo(TestVersion version) {
    if (minVersion != null && version.compareTo(TestVersion.parse(minVersion!)) < 0) return false;
    if (maxVersion != null && version.compareTo(TestVersion.parse(maxVersion!)) > 0) return false;
    return _parent?.appliesTo(version) ?? true;
  }

  /// Node with [id] in this subtree (including itself)
  TestCase? findId(String id);

  /// Node with number [number] in this subtree (including itself)
  TestCase? findNumber(String number);

  String get _type;

  Map<String, Object?> toJson() => {
    'type': _type,
    if (id != null) 'id': id,
    'name': name,
    if (minVersion != null) 'minVersion': minVersion,
    if (maxVersion != null) 'maxVersion': maxVersion,
    if (manual != null) 'manual': manual,
    if (writes) 'writes': true,
    if (pre.isNotEmpty) 'pre': pre.map((e) => e.toJson()).toList(),
    if (after.isNotEmpty) 'after': after.map((e) => e.toJson()).toList(),
  };

  /// Reads a node (already checked by [TestGroup.validate])
  static TestCase _fromValidJson(Map json) {
    List<TestAction>? actions(String k) => json[k] == null ? null : TestAction._actions(json[k]);
    final type = json['type'];
    final name = json['name'] as String, id = json['id'] as String?, minV = json['minVersion'] as String?, maxV = json['maxVersion'] as String?;
    final manual = json['manual'] as String?, writes = json['writes'] == true;
    if (type == 'unit') {
      return TestUnit(
        name: name,
        id: id,
        minVersion: minV,
        maxVersion: maxV,
        manual: manual,
        writes: writes,
        pre: actions('pre'),
        after: actions('after'),
        steps: actions('steps') ?? const [],
      );
    }
    final cases = (json['cases'] as List).map((e) => _fromValidJson(e as Map)).toList();
    return type == 'sequence'
        ? TestSequence(
            name: name,
            id: id,
            minVersion: minV,
            maxVersion: maxV,
            manual: manual,
            writes: writes,
            pre: actions('pre'),
            after: actions('after'),
            cases: cases,
          )
        : TestGroup(
            name: name,
            id: id,
            minVersion: minV,
            maxVersion: maxV,
            manual: manual,
            writes: writes,
            pre: actions('pre'),
            after: actions('after'),
            cases: cases,
          );
  }

  @override
  String toString() => '$runtimeType(${number.isEmpty ? '' : '$number '}$name)';
}

/// One test: the actions [steps]
class TestUnit extends TestCase {
  final List<TestAction> steps;

  TestUnit({
    required String name,
    String? id,
    String? minVersion,
    String? maxVersion,
    String? manual,
    bool writes = false,
    List<TestAction>? pre,
    List<TestAction>? after,
    List<TestAction> steps = const [],
  }) : steps = List.unmodifiable(steps),
       super._(name, id, minVersion, maxVersion, manual, writes, pre, after);

  @override
  String get _type => 'unit';

  @override
  TestCase? findId(String id) => this.id == id ? this : null;

  @override
  TestCase? findNumber(String number) => this.number == number ? this : null;

  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'steps': steps.map((e) => e.toJson()).toList()};
}

/// Group: children [cases] are independent – a failing child doesn't block the others; the group's [pre] / [after] run
/// before / after **each** child. A script file is one root [TestGroup]: `void main() => script.printJson();`
class TestGroup extends TestCase {
  final List<TestCase> cases;

  TestGroup({
    required String name,
    String? id,
    String? minVersion,
    String? maxVersion,
    String? manual,
    bool writes = false,
    List<TestAction>? pre,
    List<TestAction>? after,
    required List<TestCase> cases,
  }) : cases = List.unmodifiable(cases),
       super._(name, id, minVersion, maxVersion, manual, writes, pre, after) {
    for (final c in cases) {
      c._parent = this;
    }
  }

  @override
  String get _type => 'group';

  /// Every [TestUnit] in the group, in order
  List<TestUnit> get units => [
    for (final c in cases) ...(c is TestGroup ? c.units : [c as TestUnit]),
  ];

  @override
  TestCase? findId(String id) {
    if (this.id == id) return this;
    for (final c in cases) {
      final rs = c.findId(id);
      if (rs != null) return rs;
    }
    return null;
  }

  @override
  TestCase? findNumber(String number) {
    if (this.number == number) return this;
    for (final c in cases) {
      final rs = c.findNumber(number);
      if (rs != null) return rs;
    }
    return null;
  }

  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'cases': cases.map((e) => e.toJson()).toList()};

  /// JSON of the script file (root, with `schema`)
  Map<String, Object?> toRootJson() => {'schema': kTestScriptSchema, ...toJson()};

  String encode() => const JsonEncoder.withIndent('  ').convert(toRootJson());

  /// Prints the JSON – `void main() => script.printJson();`. Throws instead of printing when the script is invalid.
  void printJson() {
    final errors = validate(toRootJson());
    if (errors.isNotEmpty) throw ArgumentError('$name:\n${errors.join('\n')}');
    // ignore: avoid_print
    print(encode());
  }

  /// Reads a script file's JSON. Invalid → [FormatException]; `schema` above [kTestScriptSchema] → [UnsupportedError].
  factory TestGroup.fromJson(Map<String, Object?> json) {
    final schema = json['schema'];
    if (schema is int && schema > kTestScriptSchema) throw UnsupportedError('Needs a newer app (schema $schema)');
    final errors = validate(json);
    if (errors.isNotEmpty) throw FormatException('${json['id'] ?? json['name']}:\n${errors.join('\n')}');
    return TestCase._fromValidJson(json) as TestGroup;
  }

  factory TestGroup.decode(String source) => TestGroup.fromJson(Map<String, Object?>.from(jsonDecode(source) as Map));

  /// Ids called with `runTest` in the whole tree
  Set<String> get runTests {
    final rs = <String>{};
    void actions(List<TestAction> list) {
      for (final a in list) {
        if (a.cmd == 'runTest') rs.add(a.script!);
        actions([...a.onError, ...a.steps]);
      }
    }

    void visit(TestCase c) {
      actions(c.pre);
      actions(c.after);
      if (c is TestUnit) actions(c.steps);
      if (c is TestGroup) c.cases.forEach(visit);
    }

    visit(this);
    return rs;
  }

  /// Every id in the tree
  Set<String> get ids {
    final rs = <String>{};
    void visit(TestCase c) {
      if (c.id != null) rs.add(c.id!);
      if (c is TestGroup) c.cases.forEach(visit);
    }

    visit(this);
    return rs;
  }

  /// Checks a script file's JSON, returns the errors (empty = valid). [fileName]: also checks the root `id` equals the file name.
  static List<String> validate(Map<String, Object?> json, {String? fileName}) {
    final e = <String>[];
    if (json['schema'] != kTestScriptSchema) e.add('schema must be $kTestScriptSchema');
    if (json['type'] != 'group' && json['type'] != 'sequence') e.add('the root must be a TestGroup / TestSequence');
    if (fileName != null) {
      final base = fileName.replaceAll(RegExp(r'^.*[\\/]'), '').replaceAll(RegExp(r'\.(dart|m?js|ts|json|bist)$'), '');
      if (base != json['id']) e.add('root id "${json['id']}" differs from the file name "$base"');
    }
    final ids = <String>{};
    _validateCase(json, 'Root', ids, e, root: true);
    return e;
  }
}

/// Group that runs **in order**: a child relies on the previous ones (same `{{now}}`); after a failure the remaining
/// children are skipped. Running one child alone runs the children before it first. [pre] / [after] run once.
class TestSequence extends TestGroup {
  TestSequence({required super.name, super.id, super.minVersion, super.maxVersion, super.manual, super.writes, super.pre, super.after, required super.cases});

  @override
  String get _type => 'sequence';
}

void _validateCase(Object? raw, String p, Set<String> ids, List<String> e, {bool root = false}) {
  if (raw is! Map) {
    e.add('$p: must be a TestUnit / TestGroup / TestSequence');
    return;
  }
  final type = raw['type'];
  final name = raw['name'];
  final where = name is String ? '$p "$name"' : p;
  if (!const ['unit', 'group', 'sequence'].contains(type)) e.add('$where: type must be unit | group | sequence');
  if (name is! String || name.trim().isEmpty) e.add('$where: name is required');
  final id = raw['id'];
  if (id != null) {
    if (id is! String || !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(id)) e.add('$where: id may only contain letters, digits, . _ -');
    if (!ids.add('$id')) e.add('$where: id "$id" is duplicated');
  } else if (root) {
    e.add('$where: the root needs an id (same as the file name)');
  }
  for (final k in const ['minVersion', 'maxVersion']) {
    final v = raw[k];
    if (v != null && (v is! String || !TestVersion.isValid(v))) e.add('$where: $k must look like 1.0.0+10');
  }
  if (raw['manual'] != null && raw['manual'] is! String) e.add('$where: manual must be a string (the reason)');
  if (raw['writes'] != null && raw['writes'] is! bool) e.add('$where: writes must be true | false');
  final allowed = {
    'type',
    'id',
    'name',
    'minVersion',
    'maxVersion',
    'manual',
    'writes',
    'pre',
    'after',
    if (root) 'schema',
    if (type == 'unit') 'steps' else 'cases',
  };
  for (final k in raw.keys) {
    if (!allowed.contains(k)) e.add('$where: unknown field "$k"');
  }
  void actions(String k, {bool required = false}) {
    final list = raw[k];
    if (list == null) {
      if (required && raw['manual'] == null) e.add('$where: $k needs at least 1 action');
      return;
    }
    if (list is! List) {
      e.add('$where: $k must be a list of actions');
      return;
    }
    if (required && list.isEmpty && raw['manual'] == null) e.add('$where: $k needs at least 1 action');
    for (var i = 0; i < list.length; i++) {
      _validateStep(list[i], '$where $k[${i + 1}]', false, null, e);
    }
  }

  actions('pre');
  actions('after');
  if (type == 'unit') {
    actions('steps', required: true);
  } else if (type == 'group' || type == 'sequence') {
    final cases = raw['cases'];
    if (cases is! List || cases.isEmpty) {
      e.add('$where: cases needs at least 1 item');
    } else {
      for (var i = 0; i < cases.length; i++) {
        _validateCase(cases[i], '$p.${i + 1}'.replaceFirst('Root.', ''), ids, e);
      }
    }
  }
}

void _validateStep(Object? raw, String p, bool nested, String? scriptId, List<String> e) {
  if (raw is! Map || !_fields.containsKey(raw['cmd'])) {
    e.add('$p: unknown command – available: ${kTestCommands.join(', ')}');
    return;
  }
  final st = Map<String, Object?>.from(raw);
  final cmd = st['cmd'] as String;
  final f = _fields[cmd]!;
  final allowed = [...f.main, ...f.extra, if (f.find) ...kFindKeys, ..._opt];
  for (final k in st.keys) {
    if (k != 'cmd' && !allowed.contains(k)) e.add('$p: $cmd has no parameter "$k" (allowed: ${allowed.join(', ')})');
  }
  for (final k in f.main) {
    if (st[k] == null) e.add('$p: $cmd is missing "$k"');
  }
  for (final k in const [
    'text',
    'id',
    'icon',
    'route',
    'inside',
    'note',
    'value',
    'script',
    'path',
    'name',
    'tag',
    'start',
    'end',
    'chars',
    'format',
    'url',
    'key',
    'message',
    'yes',
    'no',
    'initial',
    'hint',
    'api',
  ]) {
    final v = st[k];
    if (v != null && v is! String) e.add('$p: $k must be a string');
    if (v is String && v.isEmpty && k != 'value') e.add('$p: $k must not be empty');
  }
  final hasTarget = ['text', 'id', 'icon', 'type'].any((k) => st[k] != null);
  if (const ['tap', 'tapLong', 'tapDouble'].contains(cmd) && !hasTarget) e.add('$p: $cmd needs at least one of text, id, icon, type');
  if ((cmd == 'expect' || cmd == 'notExpect') && !hasTarget && st['route'] == null) e.add('$p: $cmd needs at least one of ${kFindKeys.join(', ')}');
  for (final k in _fieldState) {
    if (cmd.endsWith('xpect') && st[k] != null && !hasTarget) e.add('$p: $k needs a widget to check (text, id, icon, type)');
  }
  for (final k in const ['focused', 'obscured', 'enabled', 'shot', 'checked', 'selected', 'on']) {
    if (st[k] != null && st[k] is! bool) e.add('$p: $k must be true | false');
  }
  if (st['match'] != null) {
    if (!TextMatch.values.any((m) => m.name == st['match'])) e.add('$p: match must be ${TextMatch.values.map((m) => m.name).join(' | ')}');
    if (st['text'] == null && st['value'] == null) e.add('$p: match needs text or value');
    if (st['match'] == 'regex') {
      for (final k in const ['text', 'value']) {
        final v = st[k];
        if (v is String && !v.contains('{{')) {
          try {
            RegExp(v);
          } on FormatException {
            e.add('$p: $k is not a valid regex');
          }
        }
      }
    }
  }
  if (st['count'] != null && (st['count'] is! int || (st['count'] as int) < 0)) e.add('$p: count must be an integer ≥ 0');
  if (cmd == 'mockApi') {
    if (st['status'] != null && (st['status'] is! int || (st['status'] as int) < 100 || (st['status'] as int) > 599)) e.add('$p: status must be 100..599');
    if (st['delay'] != null && (st['delay'] is! int || (st['delay'] as int) < 0)) e.add('$p: delay must be a number of ms ≥ 0');
    if (st['times'] != null && (st['times'] is! int || (st['times'] as int) < 1)) e.add('$p: times must be ≥ 1');
    if (st['method'] != null && !kHttpMethods.contains(st['method'])) e.add('$p: method must be ${kHttpMethods.join(' | ')}');
    if (st['body'] != null && st['body'] is! String) e.add('$p: body must be a string (JSON text)');
  }
  for (final k in const ['from', 'to', 'min', 'max', 'minLength', 'maxLength']) {
    if (st[k] != null && st[k] is! int) e.add('$p: $k must be an integer');
  }
  final mx = st['maxLength'], mn = st['minLength'];
  if (mx is int && mx < 0 || mn is int && (mn < 0 || (mx is int && mn > mx))) e.add('$p: minLength ≤ maxLength, ≥ 0');
  if (cmd == 'randInt' && st['min'] is int && st['max'] is int && (st['min'] as int) > (st['max'] as int)) e.add('$p: min ≤ max');
  if (cmd == 'loopWhile' && st['max'] is int && (st['max'] as int) < 1) e.add('$p: max ≥ 1');
  if (cmd == 'loop' && st['from'] is int && st['to'] is int && ((st['to'] as int) - (st['from'] as int)).abs() > 200)
    e.add('$p: loop allows at most 200 iterations');
  for (final k in const ['key', 'path']) {
    if ((cmd == 'getEnv' || cmd == 'getLog') && st[k] is String && kSecretPattern.hasMatch(st[k] as String))
      e.add('$p: secret values are not allowed ($k "${st[k]}")');
  }
  if (const ['randInt', 'randText', 'getText', 'getLog', 'getEnv', 'ask'].contains(cmd)) {
    final n = st['name'];
    if (n is String && (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(n) || _reservedVars.contains(n))) {
      e.add('$p: variable name "$n" may only contain letters, digits, _ and must not be ${_reservedVars.join(', ')}');
    }
  }
  if (cmd == 'pickFile' && st['url'] is String && !RegExp(r'^(https://|\{\{)').hasMatch(st['url'] as String)) e.add('$p: url must start with https://');
  if (st['type'] != null && !WidgetType.values.any((t) => t.name == st['type'])) e.add('$p: type must be ${WidgetType.values.map((t) => t.name).join(' | ')}');
  if (st['direction'] != null && !SwipeDirection.values.any((t) => t.name == st['direction'])) {
    e.add('$p: swipe direction must be ${SwipeDirection.values.map((t) => t.name).join(' | ')}');
  }
  if (st['level'] != null && !LogLevel.values.any((t) => t.name == st['level'])) e.add('$p: level must be ${LogLevel.values.map((t) => t.name).join(' | ')}');
  final timeout = st['timeout'];
  if (timeout != null && !(timeout is int && timeout > 0)) e.add('$p: timeout must be a number of ms > 0');
  if (cmd == 'wait' && !(st['ms'] is int && (st['ms'] as int) >= 0)) e.add('$p: wait needs a number of ms ≥ 0');
  if (cmd == 'loop' || cmd == 'loopWhile') {
    final steps = st['steps'];
    if (steps is! List || steps.isEmpty) {
      e.add('$p: $cmd needs steps (at least 1 action)');
    } else {
      for (var j = 0; j < steps.length; j++) {
        _validateStep(steps[j], '$p steps[${j + 1}]', false, scriptId, e);
      }
    }
  }
  if (cmd == 'loopWhile') {
    final c = st['condition'];
    if (c is! Map || (c['cmd'] != 'expect' && c['cmd'] != 'notExpect')) {
      e.add('$p: loopWhile needs a condition: expect(...) or notExpect(...)');
    } else {
      _validateStep(c, '$p condition', true, scriptId, e);
    }
  }
  if (cmd == 'runTest' && scriptId != null && st['script'] == scriptId) e.add('$p: a script must not call itself');
  final list = st['onError'];
  if (list != null) {
    if (nested) {
      e.add('$p: commands inside onError cannot have their own onError (one level only)');
    } else if (list is! List || list.isEmpty) {
      e.add("$p: onError must be a list of commands, e.g. [nav('login')]");
    } else {
      for (var j = 0; j < list.length; j++) {
        _validateStep(list[j], '$p onError[${j + 1}]', true, scriptId, e);
      }
    }
  }
}

Map<String, Object?> _find(String? text, String? id, WidgetType? type, String? icon, String? route, String? inside, TextMatch? match) => {
  'text': text,
  'id': id,
  'type': type,
  'icon': icon,
  'route': route,
  'inside': inside,
  'match': match == TextMatch.exact ? null : match,
};

Map<String, Object?> _o(int? timeout, String? note, bool shot, List<TestAction>? onError) => {
  'timeout': timeout,
  'note': note,
  'shot': shot,
  'onError': onError,
};

Map<String, Object?> _state(bool enabled, String? value, bool? focused, bool? obscured, int? maxLength, int? count, bool? checked, bool? selected) => {
  'enabled': enabled,
  'value': value,
  'focused': focused,
  'obscured': obscured,
  'maxLength': maxLength,
  'count': count,
  'checked': checked,
  'selected': selected,
};

// ==== Tap, input ====

/// Taps the widget matching every property given
TestAction tap({
  String? text,
  String? id,
  WidgetType? type,
  String? icon,
  String? route,
  String? inside,
  TextMatch? match,
  int? timeout,
  String? note,
  bool shot = false,
  List<TestAction>? onError,
}) => TestAction._build('tap', {..._find(text, id, type, icon, route, inside, match), ..._o(timeout, note, shot, onError)});

/// Long press (700 ms)
TestAction tapLong({
  String? text,
  String? id,
  WidgetType? type,
  String? icon,
  String? route,
  String? inside,
  TextMatch? match,
  int? timeout,
  String? note,
  bool shot = false,
  List<TestAction>? onError,
}) => TestAction._build('tapLong', {..._find(text, id, type, icon, route, inside, match), ..._o(timeout, note, shot, onError)});

/// Double tap
TestAction tapDouble({
  String? text,
  String? id,
  WidgetType? type,
  String? icon,
  String? route,
  String? inside,
  TextMatch? match,
  int? timeout,
  String? note,
  bool shot = false,
  List<TestAction>? onError,
}) => TestAction._build('tapDouble', {..._find(text, id, type, icon, route, inside, match), ..._o(timeout, note, shot, onError)});

/// Types [value] into an input (replaces the old text; `''` clears it). `text` is the input's label / hint, or the text right
/// above / before the input. Without any finding property it types into the focused input. Dropdowns: picks the item [value].
TestAction input(
  String value, {
  String? text,
  String? id,
  WidgetType? type,
  String? icon,
  String? route,
  String? inside,
  TextMatch? match,
  int? timeout,
  String? note,
  bool shot = false,
  List<TestAction>? onError,
}) => TestAction._build('input', {'value': value, ..._find(text, id, type, icon, route, inside, match), ..._o(timeout, note, shot, onError)});

/// Picks a date in a date field ([value] as `dd/MM/yyyy`, or `{{date:+1}}`)
TestAction inputDate(
  String value, {
  String? text,
  String? id,
  WidgetType? type,
  String? icon,
  String? route,
  String? inside,
  TextMatch? match,
  int? timeout,
  String? note,
  bool shot = false,
  List<TestAction>? onError,
}) => TestAction._build('inputDate', {'value': value, ..._find(text, id, type, icon, route, inside, match), ..._o(timeout, note, shot, onError)});

/// Picks a date range ([start] to [end], `dd/MM/yyyy`) in a date range field
TestAction inputDateRange(
  String start,
  String end, {
  String? text,
  String? id,
  WidgetType? type,
  String? icon,
  String? route,
  String? inside,
  TextMatch? match,
  int? timeout,
  String? note,
  bool shot = false,
  List<TestAction>? onError,
}) => TestAction._build('inputDateRange', {
  'start': start,
  'end': end,
  ..._find(text, id, type, icon, route, inside, match),
  ..._o(timeout, note, shot, onError),
});

/// Sample file for file / image pickers: downloads [url] (https, cached) when the step runs; the app's next file / image /
/// video picker returns this file instead of the OS picker (call several times → pick several files). [name]: file name the
/// app sees (default: last path segment). Put it before the step that taps the "choose file" button.
TestAction pickFile(String url, {String? name, String? note}) => TestAction._build('pickFile', {'url': url, 'name': name, 'note': note});

// ==== Checks ====

/// Waits until a widget matching every property is shown (scrolls to find it). Only `route` = waits until that screen is open.
/// Extra conditions: [enabled] button / input is enabled; for inputs: [value] current text (after the app's formatters),
/// [focused], [obscured] (password), [maxLength]; [count] number of matching widgets; [checked] checkbox / switch / radio;
/// [selected] tab / chip / list item. Error under an input: `expect(text: '<error text>')`.
TestAction expect({
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
  List<TestAction>? onError,
}) => TestAction._build('expect', {
  ..._find(text, id, type, icon, route, inside, match),
  ..._state(enabled, value, focused, obscured, maxLength, count, checked, selected),
  ..._o(timeout, note, shot, onError),
});

/// Waits until the widget is gone (e.g. "Loading" disappears). Only `route` = waits until that screen is left.
/// With extra conditions ([value], [focused], …) it passes when the widget does **not** meet them.
TestAction notExpect({
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
  List<TestAction>? onError,
}) => TestAction._build('notExpect', {
  ..._find(text, id, type, icon, route, inside, match),
  ..._state(enabled, value, focused, obscured, maxLength, count, checked, selected),
  ..._o(timeout, note, shot, onError),
});

// ==== Navigation, scrolling, waiting ====

/// Goes back (closes the top dialog / screen), like Android's Back button
TestAction back({String? note, bool shot = false, List<TestAction>? onError}) => TestAction._build('back', _o(null, note, shot, onError));

/// Swipes a finger in [direction]: `up` = see what's below, `down` = pull down (pull-to-refresh at the top of a list).
/// With finding properties it swipes inside the scrollable containing that widget, otherwise the largest scrollable.
TestAction swipe(
  SwipeDirection direction, {
  String? text,
  String? id,
  WidgetType? type,
  String? icon,
  String? route,
  String? inside,
  TextMatch? match,
  String? note,
  bool shot = false,
  List<TestAction>? onError,
}) => TestAction._build('swipe', {'direction': direction, ..._find(text, id, type, icon, route, inside, match), ..._o(null, note, shot, onError)});

/// Waits exactly [ms] milliseconds – only when there is nothing to `expect` / `notExpect`
TestAction wait(int ms, {String? note, bool shot = false}) => TestAction._build('wait', {'ms': ms, ..._o(null, note, shot, null)});

/// Runs the script / node [script] (an id, e.g. login) then continues
TestAction runTest(String script, {String? note, List<TestAction>? onError}) =>
    TestAction._build('runTest', {'script': script, ..._o(null, note, false, onError)});

// ==== For developers ====

/// Opens the screen with route [path] directly, like a deep link (good for preconditions)
TestAction nav(String path, {int? timeout, String? note, bool shot = false, List<TestAction>? onError}) =>
    TestAction._build('nav', {'path': path, ..._o(timeout, note, shot, onError)});

/// Switches the app to server [name] (needs a `BistProvider` that supports servers)
TestAction server(String name, {int? timeout, String? note, List<TestAction>? onError}) =>
    TestAction._build('server', {'name': name, ..._o(timeout, note, false, onError)});

/// Waits for a new app log (since the previous step started) whose `tag` contains [tag], with [level] if given
TestAction expectLog(String tag, {LogLevel? level, int? timeout, String? note, List<TestAction>? onError}) =>
    TestAction._build('expectLog', {'tag': tag, 'level': level, ..._o(timeout, note, false, onError)});

// ==== Fake server (removed automatically when the run ends) ====

/// Requests whose URL contains [api] (and [method], if given) get a fake response: status [status] (default 200), body
/// [body] (JSON text), after [delay] ms; removed after [times] uses (default: until the run ends). For error screens, empty
/// data, slow network. Needs a `BistProvider` that supports network mocking.
TestAction mockApi(String api, {int? status, String? body, int? delay, int? times, String? method, String? note}) =>
    TestAction._build('mockApi', {'api': api, 'status': status, 'body': body, 'delay': delay, 'times': times, 'method': method, 'note': note});

/// Simulates no network ([on] = true) or network back (false): every request fails like when offline
TestAction offline({bool on = true, String? note}) => TestAction._build('offline', {'on': on, 'note': note});

/// Removes every [mockApi] / [offline]
TestAction resetApi({String? note}) => TestAction._build('resetApi', {'note': note});

// ==== Loops, generated data ====

/// Runs [steps] with `{{i}}` = [from], [from]+1, … [to] (counts down if [from] > [to]); stops at a failing action.
/// Named `loop` because `for` is a Dart keyword.
TestAction loop(int from, int to, List<TestAction> steps, {String? note, List<TestAction>? onError}) =>
    TestAction._build('loop', {'from': from, 'to': to, 'steps': steps, ..._o(null, note, false, onError)});

/// Loop: checks [condition] (an `expect(...)` / `notExpect(...)`, use a short `timeout`); true → runs [steps]; false → stops
/// (passed). Still true after [max] iterations → fails. Named `loopWhile` because `while` is a Dart keyword.
TestAction loopWhile(TestAction condition, List<TestAction> steps, {int? max, String? note, List<TestAction>? onError}) =>
    TestAction._build('loopWhile', {'condition': condition, 'steps': steps, 'max': max, ..._o(null, note, false, onError)});

/// Random number in [min]..[max] saved to `{{name}}`. [format]: text with `{value}`, e.g. `'Order {value}'`
/// (don't write `$value` – Dart would replace it while writing).
TestAction randInt(String name, int min, int max, {String? format, String? note}) =>
    TestAction._build('randInt', {'name': name, 'min': min, 'max': max, 'format': format, 'note': note});

/// Random text of [minLength]..[maxLength] characters from [chars] (default lowercase + digits) saved to `{{name}}`.
/// [format]: text with `{value}`, e.g. `'BIST-{value}'`.
TestAction randText(String name, int minLength, int maxLength, {String? chars, String? format, String? note}) =>
    TestAction._build('randText', {'name': name, 'minLength': minLength, 'maxLength': maxLength, 'chars': chars, 'format': format, 'note': note});

// ==== Read values into variables ====

/// Saves the text of the found widget to `{{name}}`: text on screen (`Text`), or the current text of an input.
/// E.g. `getText('fullName', text: 'Full name', type: WidgetType.input)`.
TestAction getText(
  String name, {
  String? text,
  String? id,
  WidgetType? type,
  String? icon,
  String? route,
  String? inside,
  TextMatch? match,
  int? timeout,
  String? note,
  List<TestAction>? onError,
}) => TestAction._build('getText', {'name': name, ..._find(text, id, type, icon, route, inside, match), ..._o(timeout, note, false, onError)});

/// Saves a value from the newest app log whose tag contains [tag] (with [level], if given) to `{{name}}`. [path]: dotted path
/// in the log data, numbers are list positions – e.g. for an API log `POST /api/login`:
/// `getLog('userId', 'login', path: 'responseBody.data.userId')`. Waits up to [timeout] if there is no log yet.
TestAction getLog(String name, String tag, {String? path, LogLevel? level, int? timeout, String? note, List<TestAction>? onError}) =>
    TestAction._build('getLog', {'name': name, 'tag': tag, 'path': path, 'level': level, ..._o(timeout, note, false, onError)});

/// Saves environment value [key] to `{{name}}` (or use `{{env:<key>}}` directly, see [env]). Built-in keys: `route`,
/// `app.version`, `server.name`; others come from the app (`Bist.values['<key>']`, `BistProvider.env`), e.g. `user.name`.
/// Secret-looking keys (token, password…) are refused.
TestAction getEnv(String name, String key, {String? note, List<TestAction>? onError}) =>
    TestAction._build('getEnv', {'name': name, 'key': key, ..._o(null, note, false, onError)});

// ==== Print, notify, ask the tester ====

/// Writes [message] to the report and the `BIST|` log (variables allowed, e.g. `log('userId = {{uid}}')`).
/// Named `log` because `print` is a built-in Dart function.
TestAction log(String message, {String? note}) => TestAction._build('log', {'message': message, 'note': note});

/// Shows a short message on screen, doesn't wait
TestAction toast(String message, {String? note}) => TestAction._build('toast', {'message': message, 'note': note});

/// Dialog asking the tester [message] (e.g. "Is the button color right?"): [yes] (default "Yes") passes, [no] (default
/// "No") fails. No answer after [timeout] (default 5 minutes) fails – don't use it in unattended runs.
TestAction confirm(String message, {String? yes, String? no, int? timeout, String? note, List<TestAction>? onError}) =>
    TestAction._build('confirm', {'message': message, 'yes': yes, 'no': no, ..._o(timeout, note, false, onError)});

/// Dialog for the tester to type a value (e.g. an OTP sent to their phone), saved to `{{name}}`. [initial]: prefilled text,
/// [hint]: hint text. Cancel or no answer after [timeout] (default 5 minutes) fails.
TestAction ask(String name, String message, {String? initial, String? hint, int? timeout, String? note, List<TestAction>? onError}) =>
    TestAction._build('ask', {'name': name, 'message': message, 'initial': initial, 'hint': hint, ..._o(timeout, note, false, onError)});
