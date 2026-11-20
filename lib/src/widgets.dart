part of '../flutter_bist.dart';

/// Reads widgets: the app's [BistProvider] first, then the built-in Material / Cupertino rules
class _W {
  _W._();

  static BistProvider get _p => Bist.instance.provider;

  static List<String?> textsOf(Widget w) =>
      _p.textsOf(w) ??
      switch (w) {
        Text() => [w.data ?? w.textSpan?.toPlainText()],
        Tooltip() => [w.message],
        Semantics() => [w.properties.label],
        TextField() => [w.decoration?.labelText, w.decoration?.hintText],
        _ => const [],
      };

  /// Visible text of a `Text` widget (also used for "inside" and screen dumps)
  static String? textOf(Widget w) => w is Text ? (w.data ?? w.textSpan?.toPlainText()) : null;

  static WidgetType? widgetOf(Widget w) => _p.widgetOf(w);

  static bool isButton(Widget w) => widgetOf(w) == WidgetType.button;

  static bool isInput(Widget w) => widgetOf(w) == WidgetType.input;

  static bool isImage(Widget w) => widgetOf(w) == WidgetType.image;

  static bool isDropdown(Widget w) => widgetOf(w) == WidgetType.dropdown;

  /// Where `input` types / picks: a text input or a dropdown
  static bool isField(Widget w) => switch (widgetOf(w)) {
    WidgetType.input || WidgetType.dropdown => true,
    _ => false,
  };

  static bool? isEnabled(Widget w) =>
      _p.isEnabled(w) ??
      switch (w) {
        ButtonStyleButton() => w.enabled,
        IconButton() => w.onPressed != null,
        FloatingActionButton() => w.onPressed != null,
        CupertinoButton() => w.onPressed != null,
        InkWell() => w.onTap != null || w.onLongPress != null,
        GestureDetector() => w.onTap != null || w.onLongPress != null,
        TextField() => w.enabled != false,
        _ => null,
      };

  static bool? checkedOf(Widget w) =>
      _p.checkedOf(w) ??
      switch (w) {
        Checkbox() => w.value ?? false,
        CheckboxListTile() => w.value ?? false,
        Switch() => w.value,
        SwitchListTile() => w.value,
        CupertinoSwitch() => w.value,
        CupertinoCheckbox() => w.value ?? false,
        // ignore: deprecated_member_use
        Radio() => w.value == w.groupValue,
        // ignore: deprecated_member_use
        RadioListTile() => w.value == w.groupValue,
        Semantics() => w.properties.checked ?? w.properties.toggled,
        _ => null,
      };

  static bool? selectedOf(Widget w) =>
      _p.selectedOf(w) ??
      switch (w) {
        ChoiceChip() => w.selected,
        FilterChip() => w.selected,
        InputChip() => w.selected,
        ListTile() => w.selected,
        Semantics() => w.properties.selected,
        _ => null,
      };

  /// Material icon names usable in `icon:` – for icon-only buttons without text / tooltip / `Key`
  static final icons = <String, IconData>{
    'add': Icons.add,
    'add_circle': Icons.add_circle,
    'arrow_back': Icons.arrow_back,
    'arrow_back_ios': Icons.arrow_back_ios,
    'arrow_back_ios_new': Icons.arrow_back_ios_new,
    'arrow_forward': Icons.arrow_forward,
    'calendar_month': Icons.calendar_month,
    'calendar_today': Icons.calendar_today,
    'camera_alt': Icons.camera_alt,
    'check': Icons.check,
    'chevron_left': Icons.chevron_left,
    'chevron_right': Icons.chevron_right,
    'clear': Icons.clear,
    'close': Icons.close,
    'delete': Icons.delete,
    'edit': Icons.edit,
    'favorite': Icons.favorite,
    'filter_list': Icons.filter_list,
    'first_page': Icons.first_page,
    'home': Icons.home,
    'keyboard_arrow_left': Icons.keyboard_arrow_left,
    'keyboard_arrow_right': Icons.keyboard_arrow_right,
    'last_page': Icons.last_page,
    'logout': Icons.logout,
    'menu': Icons.menu,
    'more_horiz': Icons.more_horiz,
    'more_vert': Icons.more_vert,
    'navigate_before': Icons.navigate_before,
    'navigate_next': Icons.navigate_next,
    'notifications': Icons.notifications,
    'person': Icons.person,
    'refresh': Icons.refresh,
    'search': Icons.search,
    'send': Icons.send,
    'settings': Icons.settings,
    'share': Icons.share,
  };
}
