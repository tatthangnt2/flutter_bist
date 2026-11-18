part of '../flutter_bist.dart';

/// One run
class _BistRun {
  final Bist bist;
  final BistReport report;
  final DateTime startTime = DateTime.now();
  final _logs = <BistLog>[];
  void Function()? _stopLogs;
  late final TestVersion? _version = bist.appVersion;

  BistProvider get _p => bist.provider;

  /// Results of a group's `pre` actions, waiting for the next test
  final _pending = <BistStepResult>[];
  BistUnitResult? _unit;
  String _phase = 'step';
  DateTime _prevStepStart = DateTime.now();
  int _shotIndex = 0;

  /// Variables of `randInt` / `randText` / `loop` / `get*` (`{{name}}`, `{{i}}`)
  final _vars = <String, String>{};
  final _random = math.Random();

  /// Fake server of `mockApi` / `offline`
  final _api = _NetworkMock();
  int unusedFiles = 0;
  bool _pickUsed = false;

  /// Extra info about the action just run (e.g. a generated value), shown in the report
  String? _info;
  String? lastError;

  _BistRun(this.bist, this.report) {
    _stopLogs = _p.listenLogs(_logs.add);
  }

  void close() {
    _stopLogs?.call();
    if (_pickUsed) unusedFiles = _p.closePickFiles();
    _api.close();
  }

  // ==== Tree ====

  /// Runs [node] (limited to [target] when [target] is inside it). Returns false when a test failed.
  Future<bool> _exec(TestCase node, TestCase? target) async {
    final full = target == null || identical(node, target);
    final scopeTarget = full ? null : target;
    if (_version != null && !node.appliesTo(_version)) {
      _mark(node, BistStatus.notApplicable, 'Needs version ${node.minVersion ?? ''}..${node.maxVersion ?? ''}, app is $_version');
      return true;
    }
    if (node.manual != null) {
      _mark(node, BistStatus.manual, node.manual);
      return true;
    }
    if (node is TestUnit) return _execUnit(node);

    final g = node as TestGroup;
    var scope = g.cases;
    if (scopeTarget != null) {
      final i = g.cases.indexWhere((x) => identical(x, scopeTarget) || scopeTarget.path.any((p) => identical(p, x)));
      scope = g is TestSequence ? g.cases.sublist(0, i + 1) : [g.cases[i]];
    }
    TestCase? childTarget(TestCase c) => identical(c, scope.last) ? scopeTarget : null;

    if (g is TestSequence) {
      if (!await _actions(g.pre, g, 'pre')) {
        for (final c in scope) {
          _mark(c, BistStatus.preFailed, lastError);
        }
        await _actions(g.after, g, 'after', always: true);
        return false;
      }
      var ok = true;
      for (final c in scope) {
        if (!ok) {
          _mark(c, BistStatus.skipped, 'A previous item in the sequence failed');
          continue;
        }
        ok = await _exec(c, childTarget(c));
      }
      await _actions(g.after, g, 'after', always: true);
      return ok;
    }

    var ok = true;
    for (final c in scope) {
      if (!await _actions(g.pre, g, 'pre')) {
        _mark(c, BistStatus.preFailed, lastError);
        ok = false;
      } else {
        ok = await _exec(c, childTarget(c)) && ok;
      }
      await _actions(g.after, g, 'after', always: true);
    }
    return ok;
  }

  Future<bool> _execUnit(TestUnit u) async {
    final r = _unit = BistUnitResult(u, bist.numberOf(u), BistStatus.running)..steps.addAll(_pending);
    _pending.clear();
    report.units.add(r);
    report.changed();
    bist._lastStatus[u] = BistStatus.running;
    bist._changed();
    bist.currentUnit.value = u;
    final start = DateTime.now();

    var status = BistStatus.passed;
    if (!await _actions(u.pre, u, 'pre')) {
      status = BistStatus.preFailed;
    } else if (!await _actions(u.steps, u, 'step')) {
      status = BistStatus.failed;
    }
    if (status != BistStatus.passed) r.error = lastError;
    await _actions(u.after, u, 'after', always: true);

    r
      ..duration = DateTime.now().difference(start)
      ..status = status;
    bist._lastStatus[u] = status;
    bist.currentUnit.value = null;
    report.changed();
    bist._changed();
    return !status.isFailure;
  }

  /// Sets the status of every test in [c] (without running them)
  void _mark(TestCase c, BistStatus status, String? reason) {
    for (final u in c is TestUnit ? [c] : (c as TestGroup).units) {
      final r = BistUnitResult(u, bist.numberOf(u), status)..error = reason;
      report.units.add(r);
      bist._lastStatus[u] = status;
      Bist._print({'unit': r.number, 'name': u.name, 'status': status.name, 'reason': ?reason});
    }
    report.changed();
  }

  /// Runs the actions in order, stops at a failing one ([always]: runs them all – cleanup). True when all passed.
  Future<bool> _actions(List<TestAction> list, TestCase owner, String phase, {bool always = false}) async {
    final old = _phase;
    _phase = phase;
    var ok = true;
    for (var i = 0; i < list.length; i++) {
      final label = phase == 'step' ? '${i + 1}' : '$phase${i + 1}';
      final rs = await _runStep(owner, list[i], label, 1);
      ok = ok && rs;
      if (!rs && !always) break;
    }
    _phase = old;
    return ok;
  }

  /// Runs [c] inside a `runTest` action (no separate test row in the report)
  Future<bool> _execInline(TestCase c, String prefix, int depth) async {
    if (c.manual != null) {
      lastError = 'runTest: "${c.name}" needs a tester (${c.manual})';
      return false;
    }
    Future<bool> run(List<TestAction> list, String phase, {bool always = false}) async {
      var ok = true;
      for (var i = 0; i < list.length; i++) {
        final rs = await _runStep(c, list[i], '$prefix$phase${i + 1}', depth);
        ok = ok && rs;
        if (!rs && !always) break;
      }
      return ok;
    }

    if (c is TestUnit) {
      final ok = await run(c.pre, 'pre') && await run(c.steps, '');
      await run(c.after, 'after', always: true);
      return ok;
    }
    final g = c as TestGroup;
    var ok = true;
    if (g is TestSequence && !await run(g.pre, 'pre')) return false;
    for (var i = 0; i < g.cases.length && (ok || g is! TestSequence); i++) {
      if (g is! TestSequence && !await run(g.pre, 'pre')) {
        ok = false;
        continue;
      }
      ok = await _execInline(g.cases[i], '$prefix${i + 1}.', depth) && ok;
      if (g is! TestSequence) await run(g.after, 'after', always: true);
    }
    if (g is TestSequence) await run(g.after, 'after', always: true);
    return ok;
  }

  Future<bool> _runStep(TestCase owner, TestAction step, String label, int depth, {bool nested = false}) async {
    final start = DateTime.now();
    final logStart = _prevStepStart;
    _prevStepStart = start;
    final errorCount = _logs.where((e) => e.isError).length;
    lastError = null;
    _info = null;

    String? error;
    if (owner.isWrites && step.cmd != 'server' && _p.isProduction) {
      error = 'Production server: scripts that write data only run on a non-production server (${_p.serverName ?? 'current server'})';
    } else {
      try {
        if (step.cmd == 'runTest') {
          error = await _runTest(step, label, depth);
        } else if (step.cmd == 'loop' || step.cmd == 'loopWhile') {
          error = await _loop(owner, step, label, depth);
        } else {
          await _waitIdle();
          error = await _exec1(step, logStart);
        }
      } on BistUnsupportedError catch (e) {
        error = '${e.message}';
      } catch (e, trace) {
        error = 'Exception: $e';
        debugPrint('[BIST] ${owner.name} $label: $e\n$trace');
      }
    }

    final newErrors = _logs.where((e) => e.isError).skip(errorCount).map((e) => e.tag).toSet().take(5).toList();
    final shotPath = bist.screenshots && (error != null || step.shot) ? await _shot(bist.numberOf(owner), label) : null;
    final screen = error != null && step.cmd != 'runTest' ? _screenTexts() : const <String>[];
    final result = BistStepResult(
      phase: _phase,
      label: label,
      cmd: [step.describe(), ?_info].join(' → '),
      ok: error == null,
      ms: DateTime.now().difference(start).inMilliseconds,
      error: error,
      shot: shotPath,
      screen: screen,
      appErrors: newErrors,
    );
    // A group's pre: attached to the next test; anything else: the test running / just run
    if (_unit == null || (owner is TestGroup && _phase == 'pre')) {
      _pending.add(result);
    } else {
      _unit!.steps.add(result);
    }
    Bist._print({
      'unit': bist.numberOf(owner),
      'step': label,
      'cmd': result.cmd,
      'ok': result.ok,
      'ms': result.ms,
      'error': ?error,
      'note': ?step.note,
      if (newErrors.isNotEmpty) 'appErrors': newErrors,
      'shot': ?shotPath,
      if (screen.isNotEmpty) 'screen': screen,
    });

    if (error == null) return true;
    if (!nested && step.onError.isNotEmpty) {
      var ok = true;
      for (var j = 0; j < step.onError.length && ok; j++) {
        ok = await _runStep(owner, step.onError[j], '$label.e${j + 1}', depth, nested: true);
      }
      if (ok) return true;
    }
    lastError = error;
    return false;
  }

  Future<String?> _runTest(TestAction step, String label, int depth) async {
    final c = bist.find(step.script!);
    if (c == null) return 'No test: ${step.script}';
    if (depth >= 3) return 'runTest nested more than 3 levels: ${step.script}';
    final ok = await _execInline(c, '$label.', depth + 1);
    return ok ? null : 'Failed in ${step.script}: $lastError';
  }

  // ==== Commands ====

  Future<String?> _exec1(TestAction step, DateTime logStart) async {
    final timeout = Duration(milliseconds: step.timeout ?? 5000);
    final q = _Query.of(step, _value);
    switch (step.cmd) {
      case 'tap':
      case 'tapLong':
      case 'tapDouble':
        final (e, err) = await _find(q, timeout, hittable: true);
        if (e == null) return err;
        await _hideKeyboardIfCovering(e);
        final name = q.describe();
        var rs = step.cmd == 'tapLong' ? await BistTouch.longPress(e, name: name) : await BistTouch.tap(e, name: name);
        if (step.cmd == 'tapDouble' && rs == null) {
          await BistTouch.wait(const Duration(milliseconds: 100));
          rs = await BistTouch.tap(e, name: name);
        }
        return rs;

      case 'input':
        return _input(q, _value(step.value!), timeout);

      case 'inputDate':
      case 'inputDateRange':
        return _inputDate(q, step, timeout);

      case 'getText':
        final (e, err) = await _find(q, timeout, hittable: false);
        if (e == null) return err;
        final text = _textOfElement(e);
        if (text == null) return 'Cannot read the text of ${q.describe()}';
        return _setVar(step, text);

      case 'getLog':
        final tag = _value(step.tag!);
        final end = DateTime.now().add(timeout);
        while (true) {
          final (found, v) = _findLog(tag, step.level?.name, step.dataPath == null ? null : _value(step.dataPath!));
          if (found) return v == null ? 'Log "$tag" has no ${step.dataPath}' : _setVar(step, v);
          if (DateTime.now().isAfter(end)) return 'No log: $tag';
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }

      case 'getEnv':
        final key = _value(step.key!);
        final v = _env(key);
        return v == null ? 'No value: $key' : _setVar(step, v);

      case 'log':
        _info = _value(step.message!);
        return null;

      case 'toast':
        final msg = _value(step.message!);
        _p.toast(msg);
        _info = msg;
        return null;

      case 'confirm':
      case 'ask':
        return _askTester(step, Duration(milliseconds: step.timeout ?? 300000));

      case 'pickFile':
        _pickUsed = true;
        _info = await _p.addPickFile(_value(step.url!), name: step.name == null ? null : _value(step.name!));
        return null;

      case 'randInt':
        final v = step.min! + _random.nextInt(step.max! - step.min! + 1);
        return _setVar(step, '$v');

      case 'randText':
        final chars = step.chars ?? 'abcdefghijklmnopqrstuvwxyz0123456789';
        final len = step.minLength! + _random.nextInt(step.maxLength! - step.minLength! + 1);
        return _setVar(step, String.fromCharCodes(List.generate(len, (_) => chars.codeUnitAt(_random.nextInt(chars.length)))));

      case 'expect':
        if (!q.hasTarget) return _waitRoute(q.route!, timeout, equal: true);
        if (step.count != null) return _waitCount(q, step, timeout, equal: true);
        final (e, err) = await _find(q, timeout, hittable: false, where: _stateCheck(step));
        return e == null ? err : null;

      case 'notExpect':
        if (!q.hasTarget) return _waitRoute(q.route!, timeout, equal: false);
        if (step.count != null) return _waitCount(q, step, timeout, equal: false);
        final state = _stateCheck(step);
        if (state != null) {
          // With state conditions: the widget must be there, but not meet them
          final (e, err) = await _find(q, timeout, hittable: false, where: (e) => !state(e), whereLabel: 'Still meets the condition');
          return e == null ? err : null;
        }
        final end = DateTime.now().add(timeout);
        while (DateTime.now().isBefore(end)) {
          if (_visible(_match(q)).isEmpty) return null;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        return 'Still visible: ${q.describe()}';

      case 'back':
        if (!await _p.back()) return 'Cannot go back';
        await BistTouch.wait(BistTouch.settle);
        return null;

      case 'swipe':
        return _swipe(step.direction!, q, timeout);

      case 'wait':
        await Future<void>.delayed(Duration(milliseconds: step.ms ?? 0));
        return null;

      case 'nav':
        final path = _value(step.path!);
        await _p.go(path.startsWith('/') ? path : '/$path');
        final err = await _waitRoute(path, timeout, equal: true);
        return err == null ? null : 'Unknown route: $path (now on ${_route()})';

      case 'server':
        return _p.switchServer(_value(step.name!), timeout);

      case 'mockApi':
        _api.add(_ApiMock(_value(step.api!), step.status ?? 200, step.body == null ? null : _value(step.body!), step.delay, step.times, step.method));
        _info = 'mock ${step.method ?? '*'} ${step.api} → ${step.status ?? 200}';
        return null;

      case 'offline':
        _api.offline = step.on;
        return null;

      case 'resetApi':
        _api.reset();
        return null;

      case 'expectLog':
        final tag = _value(step.tag!);
        final end = DateTime.now().add(timeout);
        while (DateTime.now().isBefore(end)) {
          final hit = _logs.where((e) => !e.time.isBefore(logStart) && e.tag.contains(tag) && (step.level == null || e.level == step.level!.name));
          if (hit.isNotEmpty) return null;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        return 'No log: $tag${step.level == null ? '' : ' (${step.level!.name})'}';
    }
    return 'Unknown command: ${step.cmd}';
  }

  String _route() => _p.currentRoute ?? '';

  Future<String?> _waitRoute(String route, Duration timeout, {required bool equal}) async {
    final r = _trimRoute(_value(route));
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      if ((_trimRoute(_route()) == r) == equal) return null;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return equal ? 'Route: ${_route()} ≠ /$r' : 'Still on route /$r';
  }

  Future<String?> _input(_Query q, String value, Duration timeout) async {
    Element? field;
    if (!q.hasTarget) {
      field = _all((e) => e.widget is EditableText && (e.widget as EditableText).focusNode.hasFocus).firstOrNull;
      if (field == null) return 'Not found: the focused input';
    } else {
      final (e, err) = await _find(q, timeout, hittable: false, input: true);
      if (e == null) return err;
      field = e;
    }
    final name = q.describe();

    final custom = _p.enterText(field, value);
    if (custom != null) return custom;

    // Dropdown: tap to open, then tap the item with text [value]
    if (_ancestorOrSelf(field, _W.isDropdown) != null) {
      final open = await BistTouch.tap(field, name: name);
      if (open != null) return open;
      await _waitIdle();
      final (item, err) = await _find(_Query(text: value), timeout, hittable: true);
      if (item == null) return 'Dropdown $name: $err';
      return BistTouch.tap(item, name: value);
    }

    final editable = BistTouch.findEditableText(field) ?? _editableNear(field);
    if (editable == null) return 'Not found: input $name';
    return BistTouch.enterText(editable, value, name: name);
  }

  /// Date fields are app-specific: [BistProvider.inputDate] sets the value; a plain text input gets the text typed
  Future<String?> _inputDate(_Query q, TestAction step, Duration timeout) async {
    final (field, err) = await _find(q, timeout, hittable: false, input: true);
    if (field == null) return err;
    final range = step.cmd == 'inputDateRange';
    final text = _value(range ? step.start! : step.value!);
    final d = _parseDmy(text);
    final end = range ? _parseDmy(_value(step.end!)) : null;
    if (d == null || (range && end == null)) return 'Bad date: "$text${range ? ' – ${step.end}' : ''}" (dd/MM/yyyy)';
    final custom = _p.inputDate(field, text, d, end: end);
    if (custom != null) {
      final rs = await custom;
      await BistTouch.wait(BistTouch.settle);
      return rs;
    }
    if (range) return 'Not a date range field: ${q.describe()}';
    final ed = BistTouch.findEditableText(field);
    if (ed == null) return 'Not a date field: ${q.describe()}';
    return BistTouch.enterText(ed, text, name: q.describe());
  }

  /// Text of [e]: `Text`, the text in an input, or the first `Text` inside
  String? _textOfElement(Element e) {
    final t = _W.textOf(e.widget);
    if (t != null) return t.trim();
    final ed = BistTouch.findEditableText(e);
    if (ed != null) return (ed.widget as EditableText).controller.text;
    String? rs;
    void visit(Element c) {
      if (rs != null) return;
      rs = _W.textOf(c.widget)?.trim();
      if (rs == null) c.visitChildren(visit);
    }

    e.visitChildren(visit);
    return rs;
  }

  /// Newest log whose tag contains [tag] (this run first, then the app's earlier logs). Returns (found, value at [path]).
  (bool, String?) _findLog(String tag, String? level, String? path) {
    bool match(BistLog e) => e.tag.contains(tag) && (level == null || e.level == level);
    final hit = _logs.reversed.where(match).firstOrNull ?? _p.logHistory.where(match).lastOrNull;
    if (hit == null) return (false, null);
    if (path == null) return (true, hit.tag);
    if (kSecretPattern.hasMatch(path)) return (true, null);
    Object? cur = hit.data;
    for (final seg in path.split('.')) {
      if (cur is String) {
        try {
          cur = jsonDecode(cur);
        } on FormatException {
          // plain text
        }
      }
      final i = int.tryParse(seg);
      cur = switch (cur) {
        Map() => cur[seg],
        List() when i != null && i >= 0 && i < cur.length => cur[i],
        _ => null,
      };
      if (cur == null) return (true, null);
    }
    return (true, cur is Map || cur is List ? jsonEncode(cur) : '$cur');
  }

  /// Environment value for `getEnv` / `{{env:<key>}}` (secret keys → null)
  String? _env(String key) {
    if (kSecretPattern.hasMatch(key)) return null;
    final custom = bist.values[key];
    if (custom != null) return custom();
    final v = _p.env(key);
    if (v != null) return v;
    return switch (key) {
      'route' => _route(),
      'app.version' => _p.appVersion,
      'server.name' => _p.serverName,
      _ => null,
    };
  }

  /// Tester dialog: `confirm` (Yes / No) or `ask` (type a value, saved to a variable)
  Future<String?> _askTester(TestAction step, Duration timeout) async {
    final context = _p.dialogContext;
    if (context == null) return 'No Navigator to show the dialog (add Bist.navigatorObserver or override BistProvider.dialogContext)';
    final isAsk = step.cmd == 'ask';
    final controller = TextEditingController(text: step.initial == null ? null : _value(step.initial!));
    final message = _value(step.message!);
    final yes = step.yes ?? 'Yes', no = step.no ?? 'No';
    var open = true;
    Bist._print({'unit': _unit?.number, 'waiting': step.cmd, 'message': message});
    final answer = showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: Text('BIST · ${_unit?.number ?? report.number}', style: const TextStyle(fontSize: 14, color: Colors.grey)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            if (isAsk)
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(hintText: step.hint == null ? null : _value(step.hint!)),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(isAsk ? null : 'no'), child: Text(isAsk ? 'Cancel' : no)),
          FilledButton(onPressed: () => Navigator.of(c).pop(isAsk ? controller.text : 'yes'), child: Text(isAsk ? 'OK' : yes)),
        ],
      ),
    ).whenComplete(() => open = false);

    String? rs;
    var timedOut = false;
    try {
      rs = await answer.timeout(timeout);
    } on TimeoutException {
      timedOut = true;
      if (open && context.mounted) Navigator.of(context, rootNavigator: true).pop();
    }
    controller.dispose();
    if (timedOut) return 'No answer after ${timeout.inSeconds} s: $message';
    if (!isAsk) {
      _info = rs == 'yes' ? yes : no;
      return rs == 'yes' ? null : 'The tester answered "$no": $message';
    }
    if (rs == null) return 'Cancelled by the tester: $message';
    return _setVar(step, rs);
  }

  String? _setVar(TestAction step, String v) {
    final value = step.format == null ? v : _value(step.format!).replaceAll('{value}', v);
    _vars[step.name!] = value;
    _info = '{{${step.name}}} = "$value"';
    return null;
  }

  /// `loop` / `loopWhile`: runs the child actions, each one is written to the report
  Future<String?> _loop(TestCase owner, TestAction step, String label, int depth) async {
    if (step.cmd == 'loop') {
      final from = step.from!, to = step.to!;
      final dir = to >= from ? 1 : -1;
      for (var i = from; dir > 0 ? i <= to : i >= to; i += dir) {
        _vars['i'] = '$i';
        for (var k = 0; k < step.steps.length; k++) {
          if (!await _runStep(owner, step.steps[k], '$label.$i.${k + 1}', depth)) return 'Failed at {{i}} = $i: $lastError';
        }
      }
      return null;
    }
    final max = step.max ?? kLoopWhileMax;
    final cond = step.condition!;
    for (var n = 1; n <= max + 1; n++) {
      // Condition false → stop, passed
      if (await _exec1(cond, _prevStepStart) != null) return null;
      if (n > max) break;
      for (var k = 0; k < step.steps.length; k++) {
        if (!await _runStep(owner, step.steps[k], '$label.$n.${k + 1}', depth)) return 'Failed at iteration $n: $lastError';
      }
    }
    return 'Still true after $max iterations: ${cond.describe()}';
  }

  Future<String?> _swipe(SwipeDirection direction, _Query q, Duration timeout) async {
    final axis = switch (direction) {
      SwipeDirection.up => AxisDirection.down,
      SwipeDirection.down => AxisDirection.up,
      SwipeDirection.left => AxisDirection.right,
      SwipeDirection.right => AxisDirection.left,
    };
    Element? e;
    if (q.hasTarget) {
      final (t, err) = await _find(q, timeout, hittable: false, autoScroll: false);
      if (t == null) return err;
      Element? s;
      t.visitAncestorElements((a) {
        if (a.widget is Scrollable && axisDirectionToAxis((a.widget as Scrollable).axisDirection) == axisDirectionToAxis(axis)) s = a;
        return s == null;
      });
      e = s;
    } else {
      e = _largestScrollable(axis);
    }
    if (e == null) return 'Not found: scrollable';
    return BistTouch.scroll(e, direction: axis, distance: (BistTouch.rectOf(e)?.height ?? 600) * .6);
  }

  // ==== Finding elements ====

  /// Every element on screen (from [BistProvider.rootContext]) that passes [test]
  List<Element> _all(bool Function(Element e) test) {
    final rs = <Element>[];
    void visit(Element e) {
      if (test(e)) rs.add(e);
      e.visitChildren(visit);
    }

    _p.rootContext.visitChildElements(visit);
    return rs;
  }

  /// Largest hittable scrollable on screen along the axis of [direction]
  Element? _largestScrollable([AxisDirection direction = AxisDirection.down]) {
    final axis = axisDirectionToAxis(direction);
    final list = _all((e) => e.widget is Scrollable && axisDirectionToAxis((e.widget as Scrollable).axisDirection) == axis && BistTouch.isHittable(e));
    double area(Element e) {
      final s = BistTouch.rectOf(e)?.size;
      return s == null ? 0 : s.width * s.height;
    }

    list.sort((a, b) => area(b).compareTo(area(a)));
    return list.firstOrNull;
  }

  /// expect / notExpect with `count`: number of matching widgets on screen (meeting the state conditions) equals / differs
  /// from `count`, waiting up to [timeout]
  Future<String?> _waitCount(_Query q, TestAction step, Duration timeout, {required bool equal}) async {
    final want = step.count!;
    final state = _stateCheck(step);
    final end = DateTime.now().add(timeout);
    var n = 0;
    while (true) {
      final list = _visible(_match(q));
      n = (state == null ? list : list.where(state)).length;
      if ((n == want) == equal) return null;
      if (DateTime.now().isAfter(end)) break;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return equal ? 'Count is $n, expected $want: ${q.describe()}' : 'Count is still $want: ${q.describe()}';
  }

  /// Extra conditions of expect / notExpect (enabled, value, focused, obscured, maxLength, checked, selected); `null` if none
  bool Function(Element e)? _stateCheck(TestAction step) {
    final value = step.fieldValue == null ? null : _value(step.fieldValue!);
    final noField = value == null && step.focused == null && step.obscured == null && step.maxLength == null;
    if (!step.enabled && noField && step.checked == null && step.selected == null) return null;
    final valueQ = value == null ? null : _Query(text: value, match: step.match);
    return (e) {
      if (step.enabled && _isEnabled(e) != true) return false;
      if (step.checked != null && _checkedOf(e) != step.checked) return false;
      if (step.selected != null && _selectedOf(e) != step.selected) return false;
      if (noField) return true;
      final ed = BistTouch.findEditableText(e) ?? _editableNear(e);
      final w = ed?.widget;
      if (w is! EditableText) return false;
      if (valueQ != null && !valueQ.textMatches(w.controller.text)) return false;
      if (step.focused != null && w.focusNode.hasFocus != step.focused) return false;
      if (step.obscured != null && w.obscureText != step.obscured) return false;
      if (step.maxLength != null && _maxLengthOf(ed!) != step.maxLength) return false;
      return true;
    };
  }

  /// Max characters of an input: `LengthLimitingTextInputFormatter` or `TextField.maxLength`
  static int? _maxLengthOf(Element editable) {
    final w = editable.widget as EditableText;
    for (final f in w.inputFormatters ?? const <TextInputFormatter>[]) {
      if (f is LengthLimitingTextInputFormatter) return f.maxLength;
    }
    final tf = _ancestorOrSelf(editable, (w) => w is TextField)?.widget as TextField?;
    return tf?.maxLength;
  }

  /// State of an input / button for error messages, e.g. `value "abc", focused false`
  String _stateOf(Element e) {
    final ed = BistTouch.findEditableText(e) ?? _editableNear(e);
    final w = ed?.widget;
    return [
      'enabled ${_isEnabled(e)}',
      if (w is EditableText) ...[
        'value "${w.controller.text}"',
        'focused ${w.focusNode.hasFocus}',
        'obscured ${w.obscureText}',
        'maxLength ${_maxLengthOf(ed!)}',
      ],
      if (_checkedOf(e) != null) 'checked ${_checkedOf(e)}',
      if (_selectedOf(e) != null) 'selected ${_selectedOf(e)}',
    ].join(', ');
  }

  /// On / off state of the checkbox / switch / radio nearest to [e] (itself, inside, or a close container); `null` if none
  static bool? _checkedOf(Element e) => _nearState(e, _W.checkedOf);

  /// Selected: tab of a TabBar / NavigationBar, chip, ListTile, Semantics `selected`; `null` if none
  static bool? _selectedOf(Element e) => _tabSelected(e) ?? _nearState(e, _W.selectedOf);

  /// Whether the tab containing [e] is open: position of the tab in `TabBar.tabs` / `NavigationBar.destinations` vs the index
  static bool? _tabSelected(Element e) {
    final chain = <Widget>[];
    bool? r;
    var level = 0;
    e.visitAncestorElements((a) {
      final w = a.widget;
      int indexIn(List<Widget> items) => items.indexWhere((t) => chain.any((c) => identical(c, t)));
      if (w is TabBar) {
        final i = indexIn(w.tabs);
        final ctl = w.controller ?? DefaultTabController.maybeOf(a);
        if (i >= 0 && ctl != null) r = ctl.index == i;
        return false;
      }
      if (w is NavigationBar) {
        final i = indexIn(w.destinations);
        if (i >= 0) r = w.selectedIndex == i;
        return false;
      }
      chain.add(w);
      return ++level < 60;
    });
    return r;
  }

  /// State near [e]: itself and inside (6 levels); then up to 50 ancestors – each ancestor itself (SwitchListTile, ChoiceChip,
  /// Semantics of a tab), the 4 closest also inside (a switch next to the text in the same row)
  static bool? _nearState(Element e, bool? Function(Widget w) of) {
    bool? inside(Element root, int depth) {
      final v = of(root.widget);
      if (v != null) return v;
      if (depth == 0) return null;
      bool? r;
      root.visitChildren((c) => r ??= inside(c, depth - 1));
      return r;
    }

    var r = inside(e, 6);
    if (r != null) return r;
    var level = 0;
    e.visitAncestorElements((a) {
      r = of(a.widget) ?? (level < 4 ? inside(a, 4) : null);
      return r == null && ++level < 50;
    });
    return r;
  }

  /// Elements matching **every** property of [q]
  List<Element> _match(_Query q) {
    final icon = q.icon == null ? null : _W.icons[q.icon];
    if (q.icon != null && icon == null) return const [];
    final key = q.id;

    // Start from the narrowest property, then filter by the others
    final List<Element> base;
    if (q.text != null) {
      base = _all((e) => _W.textsOf(e.widget).any((t) => t != null && q.textMatches(t.trim())));
    } else if (key != null) {
      base = _all((e) => _keyOf(e.widget) == key);
    } else if (icon != null) {
      base = _all((e) => e.widget is Icon && (e.widget as Icon).icon?.codePoint == icon.codePoint);
    } else {
      base = _all((e) => _isType(e, q.type!));
    }

    return base.where((e) {
      if (key != null && q.text != null && !_hasKeyAround(e, key)) return false;
      if (icon != null && (q.text != null || key != null) && !_hasIconAround(e, icon)) return false;
      if (q.type != null && !_isType(e, q.type!)) return false;
      if (q.route != null && !_inRoute(e, q.route!)) return false;
      if (q.inside != null && !_isInside(e, q.inside!)) return false;
      return true;
    }).toList();
  }

  static String? _keyOf(Widget w) => w.key is ValueKey ? '${(w.key as ValueKey).value}' : null;

  /// [e] or a close ancestor (12 levels) has `Key` [key]
  static bool _hasKeyAround(Element e, String key) {
    if (_keyOf(e.widget) == key) return true;
    var found = false, level = 0;
    e.visitAncestorElements((a) {
      found = _keyOf(a.widget) == key;
      return !found && ++level < 12;
    });
    return found;
  }

  /// The button containing [e] (or [e]) has icon [icon]
  static bool _hasIconAround(Element e, IconData icon) {
    final root = _buttonOf(e) ?? e;
    var found = false;
    void visit(Element c) {
      if (found) return;
      if (c.widget is Icon && (c.widget as Icon).icon?.codePoint == icon.codePoint) {
        found = true;
        return;
      }
      c.visitChildren(visit);
    }

    visit(root);
    return found;
  }

  /// Closest button containing [e] (or [e]), up to 12 levels
  static Element? _buttonOf(Element e) => _ancestorOrSelf(e, _W.isButton);

  static bool _isType(Element e, WidgetType type) => switch (type) {
    WidgetType.button => _buttonOf(e) != null,
    WidgetType.input => _ancestorOrSelf(e, _W.isInput) != null,
    WidgetType.text => e.widget is Text,
    WidgetType.image => _W.isImage(e.widget),
  };

  /// [e] is inside a close block (up to 10 levels) that contains text [text] – card / list row / dialog
  static bool _isInside(Element e, String text) {
    var found = false, level = 0;
    bool hasText(Element root) {
      var rs = false;
      void visit(Element c) {
        if (rs) return;
        if (_W.textOf(c.widget)?.trim() == text) {
          rs = true;
          return;
        }
        c.visitChildren(visit);
      }

      visit(root);
      return rs;
    }

    e.visitAncestorElements((a) {
      found = hasText(a);
      return !found && ++level < 10;
    });
    return found;
  }

  /// [e] is on the screen with route [route] (route of its page; unknown → the current route)
  bool _inRoute(Element e, String route) {
    final name = _p.routeOf(e);
    final r = _trimRoute(route);
    if (_trimRoute(name ?? _route()) == r) return true;
    // Tab / sub-page inside a parent route (e.g. tab `/root/settings` inside route `/root`): use the current path
    final parent = name == null ? null : _trimRoute(name);
    return parent != null && r.startsWith('$parent/') && _trimRoute(_route()) == r;
  }

  /// Elements shown: hittable, or on screen and on the top route
  List<Element> _visible(List<Element> list, {bool hittable = false}) {
    final view = View.maybeOf(_p.rootContext);
    final screen = Offset.zero & (view == null ? Size.zero : view.physicalSize / view.devicePixelRatio);
    return list.where((e) {
      if (BistTouch.isHittable(e)) return true;
      if (hittable) return false;
      final r = BistTouch.rectOf(e);
      return r != null && r.width > 0 && r.height > 0 && screen.overlaps(r) && (ModalRoute.of(e)?.isCurrent ?? true);
    }).toList();
  }

  /// Finds [q], waiting up to [timeout]; after 800 ms without a match it scrolls the largest scrollable (up to 20 swipes, back
  /// to the top once at the end of the list). Returns (element, error).
  Future<(Element?, String?)> _find(
    _Query q,
    Duration timeout, {
    required bool hittable,
    bool input = false,
    bool autoScroll = true,
    bool Function(Element e)? where,
    String? whereLabel,
  }) async {
    final start = DateTime.now();
    final end = start.add(timeout);
    var scrolls = 0;
    var rewound = false;
    var covered = false;
    while (true) {
      var all = _match(q);
      if (input) all = all.map((e) => _W.isInput(e.widget) ? e : (_inputNear(e) ?? e)).toSet().toList();
      final list = _visible(all, hittable: hittable);
      covered = all.isNotEmpty && list.isEmpty;
      if (list.isNotEmpty) {
        if (where == null) return (list.first, null);
        final ok = list.where(where);
        if (ok.isNotEmpty) return (ok.first, null);
        if (DateTime.now().isAfter(end)) return (null, '${whereLabel ?? 'Condition not met'}: ${q.describe()} (${_stateOf(list.first)})');
      }
      // Covered / not found while the keyboard is open (button under the keyboard, overflowing screen, app hides buttons
      // while typing): close the keyboard like a user and look again
      if (list.isEmpty && (covered ? hittable : DateTime.now().difference(start) > const Duration(milliseconds: 500)) && _keyboardOpen()) {
        FocusManager.instance.primaryFocus?.unfocus();
        await BistTouch.wait(BistTouch.settle);
        continue;
      }
      if (DateTime.now().isAfter(end)) break;
      if (autoScroll && list.isEmpty && DateTime.now().difference(start) > const Duration(milliseconds: 800) && scrolls < 20) {
        final s = _largestScrollable();
        final pos = s is StatefulElement && s.state is ScrollableState ? (s.state as ScrollableState).position : null;
        if (pos != null && pos.maxScrollExtent > 0) {
          if (pos.pixels >= pos.maxScrollExtent - 1) {
            if (!rewound) {
              rewound = true;
              pos.jumpTo(pos.minScrollExtent);
            }
          } else {
            await BistTouch.scroll(s!, fling: false, distance: (BistTouch.rectOf(s)?.height ?? 600) * .5);
          }
          scrolls++;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return (null, covered ? 'Covered: ${q.describe()}' : 'Not found: ${q.describe()}');
  }

  /// Closest input below / right of the label text [label] (a label placed next to the input, not its `labelText`)
  Element? _inputNear(Element label) {
    final r = BistTouch.rectOf(label);
    if (r == null) return null;
    Element? best;
    var bestD = 160.0;
    bool insideCustomInput(Element e) => _ancestorOrSelf(e, (w) => w is! EditableText && w is! TextField && _W.isInput(w), levels: 12) != null;
    final candidates = _all(
      (e) => (_W.isInput(e.widget) && e.widget is! EditableText && e.widget is! TextField) || (e.widget is EditableText && !insideCustomInput(e)),
    );
    for (final e in candidates) {
      final f = BistTouch.rectOf(e);
      if (f == null || f.bottom < r.top - 4) continue;
      final d = (f.top - r.top).abs() + (f.left - r.left).abs() * .3;
      if (d < bestD) {
        bestD = d;
        best = e;
      }
    }
    return best;
  }

  Element? _editableNear(Element e) {
    final near = _inputNear(e);
    return near == null ? null : BistTouch.findEditableText(near);
  }

  /// [e] or the closest ancestor (up to [levels]) whose widget passes [test]
  static Element? _ancestorOrSelf(Element e, bool Function(Widget w) test, {int levels = 12}) {
    if (test(e.widget)) return e;
    Element? rs;
    var level = 0;
    e.visitAncestorElements((a) {
      if (test(a.widget)) rs = a;
      return rs == null && ++level < levels;
    });
    return rs;
  }

  /// Whether the closest button / input containing [e] is enabled (`null` = unknown)
  static bool? _isEnabled(Element e) {
    bool? rs = _W.isEnabled(e.widget);
    if (rs == null) {
      var level = 0;
      e.visitAncestorElements((a) {
        rs = _W.isEnabled(a.widget);
        return rs == null && ++level < 15;
      });
    }
    return rs;
  }

  bool _keyboardOpen() {
    final view = View.maybeOf(_p.rootContext);
    return FocusManager.instance.primaryFocus != null && view != null && view.viewInsets.bottom > 0;
  }

  Future<void> _hideKeyboardIfCovering(Element e) async {
    final focus = FocusManager.instance.primaryFocus;
    final view = View.maybeOf(_p.rootContext);
    if (focus == null || view == null || view.viewInsets.bottom <= 0) return;
    final r = BistTouch.rectOf(e);
    if (r != null && r.bottom > (view.physicalSize.height - view.viewInsets.bottom) / view.devicePixelRatio) {
      focus.unfocus();
      await BistTouch.wait(BistTouch.settle);
    }
  }

  /// Waits until the screen is idle: no pending frame / animation (at most 2 s – some screens animate forever)
  static Future<void> _waitIdle({Duration max = const Duration(seconds: 2)}) async {
    final end = DateTime.now().add(max);
    var calm = 0;
    while (DateTime.now().isBefore(end) && calm < 2) {
      final b = SchedulerBinding.instance;
      calm = (!b.hasScheduledFrame && b.transientCallbackCount == 0) ? calm + 1 : 0;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  /// Texts on screen (at most 40) – written with a failed step so agents know what the screen shows without the screenshot
  List<String> _screenTexts() {
    final rs = <String>[];
    for (final e in _all((e) => e.widget is Text)) {
      final t = _W.textOf(e.widget)?.trim() ?? '';
      if (t.isEmpty || rs.contains(t) || _visible([e]).isEmpty) continue;
      rs.add(t.length > 40 ? '${t.substring(0, 40)}…' : t);
      if (rs.length >= 40) break;
    }
    return rs;
  }

  /// Screenshot into [BistProvider.tempDir]`/bist`, returns the path (`null` if it can't)
  Future<String?> _shot(String number, String label) async {
    try {
      RenderRepaintBoundary? boundary;
      void visit(RenderObject o) {
        if (boundary != null) return;
        if (o is RenderRepaintBoundary) {
          boundary = o;
          return;
        }
        o.visitChildren(visit);
      }

      for (final v in WidgetsBinding.instance.renderViews) {
        v.visitChildren(visit);
      }
      if (boundary == null || boundary!.debugNeedsPaint) return null;
      final image = await boundary!.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return null;
      final dir = Directory('${(await _p.tempDir()).path}/bist');
      await dir.create(recursive: true);
      final file = File('${dir.path}/${number}_${label.replaceAll('.', '-')}_${_shotIndex++}.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      return file.path;
    } catch (_) {
      return null;
    }
  }

  // ==== Placeholders ====

  String _value(String s) => s.replaceAllMapped(kTestValuePattern, (m) {
    final key = m[1]!;
    if (key == 'now') return _two(startTime.hour) + _two(startTime.minute) + _two(startTime.second);
    if (key.startsWith('env:')) return _env(key.substring(4)) ?? m[0]!;
    if (key.startsWith('date')) {
      final n = key.length > 5 ? int.parse(key.substring(5)) : 0;
      return _dmy(DateTime.now().add(Duration(days: n)));
    }
    if (!key.startsWith('tc:')) return _vars[key] ?? m[0]!;
    final dot = key.indexOf('.');
    final group = key.substring(3, dot < 0 ? key.length : dot);
    final field = dot < 0 ? '' : key.substring(dot + 1);
    return _p.testData(group, field) ?? m[0]!;
  });

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _dmy(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

  /// `dd/MM/yyyy` → date (`null` if invalid, e.g. 31/02)
  static DateTime? _parseDmy(String s) {
    final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(s.trim());
    if (m == null) return null;
    final d = DateTime(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
    return d.day == int.parse(m[1]!) && d.month == int.parse(m[2]!) ? d : null;
  }

  static String _trimRoute(String s) => s.replaceAll(RegExp(r'^/+|/+$'), '');
}

/// Widget-finding properties of a step (placeholders already replaced)
class _Query {
  final String? text, id, icon, route, inside;
  final WidgetType? type;
  final TextMatch match;
  final RegExp? _re;

  _Query({this.text, this.id, this.type, this.icon, this.route, this.inside, this.match = TextMatch.exact})
    : _re = match == TextMatch.regex && text != null ? RegExp(text) : null;

  /// Whether [s] (trimmed) matches `text` according to [match]
  bool textMatches(String s) => switch (match) {
    TextMatch.exact => s == text,
    TextMatch.contains => s.contains(text!),
    TextMatch.regex => _re!.hasMatch(s),
  };

  factory _Query.of(TestAction s, String Function(String) value) => _Query(
    text: s.text == null ? null : value(s.text!),
    id: s.id == null ? null : value(s.id!),
    type: s.type,
    icon: s.icon,
    route: s.route == null ? null : value(s.route!),
    inside: s.inside == null ? null : value(s.inside!),
    match: s.match,
  );

  bool get hasTarget => text != null || id != null || icon != null || type != null;

  String describe() => [
    if (text != null) match == TextMatch.exact ? 'text "$text"' : 'text ${match.name} "$text"',
    if (id != null) 'id "$id"',
    if (type != null) 'type ${type!.name}',
    if (icon != null) 'icon $icon',
    if (route != null) 'route $route',
    if (inside != null) 'inside "$inside"',
  ].join(' ');
}
