/// BIST script model – pure Dart (no Flutter import inside), exported by `package:flutter_bist/flutter_bist.dart`.
///
/// A script is a tree: [BistSuite] (children are independent) / [BistSequence] (children run in order) containing
/// [BistCase]s (one test with a list of [BistAction]s) or sub-groups. Every node is a [BistUnit] with an optional `id`,
/// `pre` / `after` (preconditions / cleanup), `writes`, `manual` and `minVersion` / `maxVersion` (`1.0.0+10`).
/// One script file = one root [BistSuite]. The in-app runner (`package:flutter_bist/flutter_bist.dart`) reads the same JSON
/// back with these classes ([BistSuite.fromJson]).
///
/// **Finding widgets:** every command that finds a widget accepts the properties below; the widget must match **all** of
/// the properties given:
/// - `text`: text shown on screen (also input labels / hints, tooltips, Semantics labels) – exact match unless `match` says otherwise
/// - `id`: the widget `Key` (`ValueKey('login.submit')`)
/// - `type`: kind of widget [WidgetType] – `button`, `input`, `text`, `image`, `checkbox`, `radio`, `dropdown`
/// - `icon`: name of a Material icon, for icon-only buttons (`add`, `logout`, …)
/// - `route`: only look inside the screen with this route
/// - `inside`: only look inside a block (card, list row, dialog) that contains this text
///
/// ```dart
/// import 'package:flutter_bist/flutter_bist.dart';
///
/// List<BistAction> login(String user, String pass) => [
///   input(user, text: 'Username'),
///   input(pass, text: 'Password'),
///   tap(text: 'SIGN IN', type: WidgetType.button),
/// ];
///
/// final script = BistSuite(id: 'login', name: 'Login', units: [
///   BistCase(name: 'Missing fields', steps: [...login('', ''), expect(text: 'Please enter username and password.')]),
///   BistCase(id: 'login.admin', name: 'Admin', steps: [
///     ...login(tc('Admin', 'userName'), tc('Admin', 'password')),
///     notExpect(text: 'SIGN IN', timeout: 15000),
///   ]),
/// ]);
///
/// void main() => script.printJson();
/// ```
library;

import 'dart:convert';

import '../flutter_bist.dart' show TestVersion;

part 'action.dart';

/// JSON format version. The runner skips scripts with a higher number ("needs a newer app").
const kTestScriptSchema = 4;

/// Kind of widget for the `type` property
/// Kind of widget for `type:` ([BistProvider.widgetOf] decides which widgets are which).
/// `checkbox` also covers switches.
enum WidgetType { button, input, text, image, checkbox, radio, dropdown }

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

/// Secret-looking keys / paths – [getEnv], [getLog] and `{{env:...}}` refuse them (no tokens, passwords in results)
final kSecretPattern = RegExp(
  r'token|password|passwd|secret|crypto|apikey|api_key|private|cookie|authorization|header|credential|mat_?khau',
  caseSensitive: false,
);

/// Test data provided by the app (`BistProvider.testData`) – keeps passwords out of scripts.
/// E.g. `input(tc('Admin', 'password'), text: 'Password')`.
String tc(String group, String field) => '{{tc:$group.$field}}';

/// Environment info used directly in text, e.g. `expect(text: env('user.name'))` (see [getEnv])
String env(String key) => '{{env:$key}}';

/// A node of the script tree: [BistCase], [BistSuite], [BistSequence]
abstract class BistUnit {
  final String name;

  /// For calling it again (`runTest(id)`) and running it alone (`--dart-define=BIST_RUN_IDS=<id>`); unique in the whole tree
  final String? id;

  /// Only runs when the app version is within [minVersion]..[maxVersion] (inclusive, `1.0.0+10`); otherwise "Not applicable"
  final String? minVersion, maxVersion;

  /// A case that can't be automated (the reason): still shown in the tree, reported as "Needs a tester", not a failure
  final String? manual;

  /// Creates / changes data: only runs on non-production servers. Set on a suite, every child counts as writing.
  final bool writes;

  /// Preconditions (best written as "check first, act only if missing") and cleanup (runs even after a failure).
  /// On a [BistSuite]: before / after **each** child; on a [BistSequence]: once before / after the whole sequence.
  final List<BistAction> pre, after;

  BistSuite? _parent;

  BistUnit._(this.name, this.id, this.minVersion, this.maxVersion, this.manual, this.writes, List<BistAction>? pre, List<BistAction>? after)
    : pre = List.unmodifiable(pre ?? const []),
      after = List.unmodifiable(after ?? const []);

  BistSuite? get parent => _parent;

  /// From the root to this node
  List<BistUnit> get path => [...?_parent?.path, this];

  /// Number by position, e.g. `2.1.3` (the root has no number)
  String get number {
    final p = _parent;
    if (p == null) return '';
    final n = '${p.units.indexOf(this) + 1}';
    return p.number.isEmpty ? n : '${p.number}.$n';
  }

  /// [writes] of this node or a parent suite
  bool get isWrites => writes || (_parent?.isWrites ?? false);

  /// Whether [version] is within the version range of this node and every parent
  bool appliesTo(TestVersion version) {
    if (minVersion != null && version.compareTo(TestVersion.parse(minVersion!)) < 0) return false;
    if (maxVersion != null && version.compareTo(TestVersion.parse(maxVersion!)) > 0) return false;
    return _parent?.appliesTo(version) ?? true;
  }

  /// Node with [id] in this subtree (including itself)
  BistUnit? findId(String id);

  /// Node with number [number] in this subtree (including itself)
  BistUnit? findNumber(String number);

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

  /// Reads a node (already checked by [BistSuite.validate])
  static BistUnit _fromValidJson(Map json) {
    List<BistAction>? actions(String k) => json[k] == null ? null : BistAction._actions(json[k]);
    final type = json['type'];
    final name = json['name'] as String, id = json['id'] as String?, minV = json['minVersion'] as String?, maxV = json['maxVersion'] as String?;
    final manual = json['manual'] as String?, writes = json['writes'] == true;
    if (type == 'case') {
      return BistCase(
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
    final units = (json['units'] as List).map((e) => _fromValidJson(e as Map)).toList();
    return type == 'sequence'
        ? BistSequence(
            name: name,
            id: id,
            minVersion: minV,
            maxVersion: maxV,
            manual: manual,
            writes: writes,
            pre: actions('pre'),
            after: actions('after'),
            units: units,
          )
        : BistSuite(
            name: name,
            id: id,
            minVersion: minV,
            maxVersion: maxV,
            manual: manual,
            writes: writes,
            pre: actions('pre'),
            after: actions('after'),
            units: units,
          );
  }

  @override
  String toString() => '$runtimeType(${number.isEmpty ? '' : '$number '}$name)';
}

/// One test: the actions [steps]
class BistCase extends BistUnit {
  final List<BistAction> steps;

  /// A tester has to do something: the test is [manual], or one of its actions (or the `pre` / `after` of its groups)
  /// is `confirm` / `ask`
  bool get needsTester {
    if (manual != null || path.any((c) => c.manual != null)) return true;
    bool has(List<BistAction> list) => list.any((a) => a.cmd == 'confirm' || a.cmd == 'ask' || has(a.steps));
    return has(steps) || path.any((c) => has(c.pre) || has(c.after));
  }

  BistCase({
    required String name,
    String? id,
    String? minVersion,
    String? maxVersion,
    String? manual,
    bool writes = false,
    List<BistAction>? pre,
    List<BistAction>? after,
    List<BistAction> steps = const [],
  }) : steps = List.unmodifiable(steps),
       super._(name, id, minVersion, maxVersion, manual, writes, pre, after);

  @override
  String get _type => 'case';

  @override
  BistUnit? findId(String id) => this.id == id ? this : null;

  @override
  BistUnit? findNumber(String number) => this.number == number ? this : null;

  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'steps': steps.map((e) => e.toJson()).toList()};
}

/// Suite: children [units] are independent – a failing child doesn't block the others; the suite's [pre] / [after] run
/// before / after **each** child. A script file is one root [BistSuite]: `void main() => script.printJson();`
class BistSuite extends BistUnit {
  final List<BistUnit> units;

  BistSuite({
    required String name,
    String? id,
    String? minVersion,
    String? maxVersion,
    String? manual,
    bool writes = false,
    List<BistAction>? pre,
    List<BistAction>? after,
    required List<BistUnit> units,
  }) : units = List.unmodifiable(units),
       super._(name, id, minVersion, maxVersion, manual, writes, pre, after) {
    for (final c in units) {
      c._parent = this;
    }
  }

  @override
  String get _type => 'suite';

  /// Every [BistCase] in the suite, in order
  List<BistCase> get cases => [
    for (final c in units) ...(c is BistSuite ? c.cases : [c as BistCase]),
  ];

  @override
  BistUnit? findId(String id) {
    if (this.id == id) return this;
    for (final c in units) {
      final rs = c.findId(id);
      if (rs != null) return rs;
    }
    return null;
  }

  @override
  BistUnit? findNumber(String number) {
    if (this.number == number) return this;
    for (final c in units) {
      final rs = c.findNumber(number);
      if (rs != null) return rs;
    }
    return null;
  }

  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'units': units.map((e) => e.toJson()).toList()};

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
  factory BistSuite.fromJson(Map<String, Object?> json) {
    final schema = json['schema'];
    if (schema is int && schema > kTestScriptSchema) throw UnsupportedError('Needs a newer app (schema $schema)');
    final errors = validate(json);
    if (errors.isNotEmpty) throw FormatException('${json['id'] ?? json['name']}:\n${errors.join('\n')}');
    return BistUnit._fromValidJson(json) as BistSuite;
  }

  factory BistSuite.decode(String source) => BistSuite.fromJson(Map<String, Object?>.from(jsonDecode(source) as Map));

  /// Ids called with `runTest` in the whole tree
  Set<String> get runTests {
    final rs = <String>{};
    void actions(List<BistAction> list) {
      for (final a in list) {
        if (a.cmd == 'runTest') rs.add(a.script!);
        actions([...a.onError, ...a.steps]);
      }
    }

    void visit(BistUnit c) {
      actions(c.pre);
      actions(c.after);
      if (c is BistCase) actions(c.steps);
      if (c is BistSuite) c.units.forEach(visit);
    }

    visit(this);
    return rs;
  }

  /// Every id in the tree
  Set<String> get ids {
    final rs = <String>{};
    void visit(BistUnit c) {
      if (c.id != null) rs.add(c.id!);
      if (c is BistSuite) c.units.forEach(visit);
    }

    visit(this);
    return rs;
  }

  /// Checks a script file's JSON, returns the errors (empty = valid). [fileName]: also checks the root `id` equals the file name.
  static List<String> validate(Map<String, Object?> json, {String? fileName}) {
    final e = <String>[];
    if (json['schema'] != kTestScriptSchema) e.add('schema must be $kTestScriptSchema');
    if (json['type'] != 'suite' && json['type'] != 'sequence') e.add('the root must be a BistSuite / BistSequence');
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
class BistSequence extends BistSuite {
  BistSequence({required super.name, super.id, super.minVersion, super.maxVersion, super.manual, super.writes, super.pre, super.after, required super.units});

  @override
  String get _type => 'sequence';
}

void _validateCase(Object? raw, String p, Set<String> ids, List<String> e, {bool root = false}) {
  if (raw is! Map) {
    e.add('$p: must be a BistCase / BistSuite / BistSequence');
    return;
  }
  final type = raw['type'];
  final name = raw['name'];
  final where = name is String ? '$p "$name"' : p;
  if (!const ['case', 'suite', 'sequence'].contains(type)) e.add('$where: type must be case | suite | sequence');
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
    if (type == 'case') 'steps' else 'units',
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
  if (type == 'case') {
    actions('steps', required: true);
  } else if (type == 'suite' || type == 'sequence') {
    final units = raw['units'];
    if (units is! List || units.isEmpty) {
      e.add('$where: units needs at least 1 item');
    } else {
      for (var i = 0; i < units.length; i++) {
        _validateCase(units[i], '$p.${i + 1}'.replaceFirst('Root.', ''), ids, e);
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

Map<String, Object?> _o(int? timeout, String? note, bool shot, List<BistAction>? onError) => {
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
