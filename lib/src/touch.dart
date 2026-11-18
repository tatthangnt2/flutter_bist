part of '../flutter_bist.dart';

/// Acts like a user on the running app (also in release builds): tap, long press, drag, type, scroll.
///
/// Touches go through [GestureBinding.handlePointerEvent] like a real finger: covered or disabled buttons and nested tap
/// areas behave as in real life. Typed text goes through [EditableTextState.updateEditingValue] (the keyboard's path into an
/// input), so `inputFormatters`, `onChanged` and validation all run.
///
/// Only controls what Flutter draws – OS dialogs, WebViews, maps and cameras can't be driven.
///
/// Methods return an error message, or `null` on success.
class BistTouch {
  BistTouch._();

  /// Wait between steps. Real time by default; widget tests may replace it (e.g. `(d) => Future.delayed(d)` with a pump loop).
  static Future<void> Function(Duration duration) wait = Future<void>.delayed;

  /// How long the finger stays down for a tap
  static const tapHold = Duration(milliseconds: 60);

  /// How long the finger stays down for a long press (more than [kLongPressTimeout])
  static const longPressHold = Duration(milliseconds: 700);

  /// Wait after each action so the app can redraw (and the double-tap timeout passes)
  static const settle = Duration(milliseconds: 350);

  static const _frame = Duration(milliseconds: 16);

  // Own pointer ids, never the same as the user's real fingers
  static int _pointer = 0x7A170000;

  // Event clock – moves forward with the waits so swipe velocity is right
  static final _clock = Stopwatch()..start();
  static Duration _elapsed = Duration.zero;
  static Duration get _timeStamp => _clock.elapsed > _elapsed ? _clock.elapsed : _elapsed;

  static Future<void> _wait(Duration d) async {
    _elapsed = _timeStamp + d;
    await wait(d);
  }

  /// Rectangle of [element] on screen (logical pixels), `null` when not laid out
  static Rect? rectOf(Element element) {
    final ro = element.renderObject;
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) return null;
    return ro.localToGlobal(Offset.zero) & ro.size;
  }

  static int _viewIdOf(Element element) => View.maybeOf(element)?.viewId ?? 0;

  /// Whether a touch at [position] (default: center) reaches [element] (not covered by something else)
  static bool isHittable(Element element, [Offset? position]) {
    final ro = element.renderObject;
    final pos = position ?? rectOf(element)?.center;
    if (ro == null || pos == null) return false;
    final result = HitTestResult();
    GestureBinding.instance.hitTestInView(result, pos, _viewIdOf(element));
    return result.path.any((e) => e.target == ro);
  }

  static void _event(PointerEvent e) => GestureBinding.instance.handlePointerEvent(e);

  /// Taps the center of [element]. Fails when it isn't shown or is covered.
  static Future<String?> tap(Element element, {Duration hold = tapHold, String? name}) async {
    final label = name ?? element.widget.runtimeType.toString();
    final rect = rectOf(element);
    if (rect == null) return '$label >>> Not displayed';
    if (!isHittable(element, rect.center)) return '$label >>> Covered, cannot tap';

    final pointer = _pointer++;
    final viewId = _viewIdOf(element);
    _event(PointerDownEvent(pointer: pointer, position: rect.center, viewId: viewId, timeStamp: _timeStamp, kind: PointerDeviceKind.touch));
    await _wait(hold);
    _event(PointerUpEvent(pointer: pointer, position: rect.center, viewId: viewId, timeStamp: _timeStamp, kind: PointerDeviceKind.touch));
    await _wait(settle);
    return null;
  }

  /// Long press on the center of [element]
  static Future<String?> longPress(Element element, {String? name}) => tap(element, hold: longPressHold, name: name);

  /// Drags a finger from the center of [element] by [offset] within [duration], then lifts it (with momentum, like a real
  /// swipe). [fling] = false: holds the finger still for a moment before lifting – no momentum, moves exactly [offset].
  static Future<String?> drag(Element element, Offset offset, {Duration duration = const Duration(milliseconds: 250), bool fling = true, String? name}) async {
    final label = name ?? element.widget.runtimeType.toString();
    final rect = rectOf(element);
    if (rect == null) return '$label >>> Not displayed';

    final pointer = _pointer++;
    final viewId = _viewIdOf(element);
    final steps = (duration.inMilliseconds / _frame.inMilliseconds).ceil().clamp(2, 60);
    final step = offset / steps.toDouble();
    var pos = rect.center;

    _event(PointerDownEvent(pointer: pointer, position: pos, viewId: viewId, timeStamp: _timeStamp, kind: PointerDeviceKind.touch));
    for (var i = 0; i < steps; i++) {
      await _wait(_frame);
      pos += step;
      _event(PointerMoveEvent(pointer: pointer, position: pos, delta: step, viewId: viewId, timeStamp: _timeStamp, kind: PointerDeviceKind.touch));
    }
    if (!fling) await _wait(const Duration(milliseconds: 150));
    _event(PointerUpEvent(pointer: pointer, position: pos, viewId: viewId, timeStamp: _timeStamp, kind: PointerDeviceKind.touch));
    await _wait(settle);
    return null;
  }

  /// Types [text] into the input in [element] (or [element] itself): taps to focus it, then sends the text like the keyboard.
  /// [append] = true adds to the current text, otherwise the text is replaced.
  static Future<String?> enterText(Element element, String text, {bool append = false, String? name}) async {
    final editable = findEditableText(element);
    final label = name ?? element.widget.runtimeType.toString();
    if (editable == null) return '$label >>> No text field';
    final state = (editable as StatefulElement).state as EditableTextState;
    if (state.widget.readOnly) return '$label >>> Read only';

    if (!state.widget.focusNode.hasFocus) {
      final err = await tap(editable, name: label);
      if (err != null) return err;
    }

    final value = append ? state.textEditingValue.text + text : text;
    state.updateEditingValue(
      TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      ),
    );
    await _wait(settle);
    return null;
  }

  /// The [EditableText] that is [element] or inside it
  static Element? findEditableText(Element element) {
    if (element.widget is EditableText) return element;
    Element? rs;
    void visit(Element e) {
      if (rs != null) return;
      if (e.widget is EditableText) {
        rs = e;
        return;
      }
      e.visitChildren(visit);
    }

    element.visitChildren(visit);
    return rs;
  }

  /// Swipes [scrollable] in [direction] (where the content goes, e.g. `down` = see what's below) by [distance] points, then
  /// waits until the list stops (items don't receive taps while scrolling). [fling] = false: no momentum.
  static Future<String?> scroll(Element scrollable, {AxisDirection direction = AxisDirection.down, double distance = 300, bool fling = true}) async {
    final offset = switch (direction) {
      AxisDirection.down => Offset(0, -distance),
      AxisDirection.up => Offset(0, distance),
      AxisDirection.right => Offset(-distance, 0),
      AxisDirection.left => Offset(distance, 0),
    };
    final err = await drag(scrollable, offset, fling: fling, name: 'Scrollable');
    if (err != null) return err;

    final position = scrollable is StatefulElement && scrollable.state is ScrollableState ? (scrollable.state as ScrollableState).position : null;
    for (var i = 0; i < 300 && position != null && position.isScrollingNotifier.value; i++) {
      await _wait(_frame);
    }
    return null;
  }
}
