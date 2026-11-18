part of '../flutter_bist.dart';

/// One fake response of `mockApi`
class _ApiMock {
  final String api;
  final int status;
  final String? body;
  final int? delay;
  int? times;
  final String? method;

  _ApiMock(this.api, this.status, this.body, this.delay, this.times, this.method);

  bool matches(String m, Uri uri) => uri.toString().contains(api) && (method == null || m.toUpperCase() == method);
}

/// Fake server of one run: matching (url, method, times, delay, offline) lives here; [BistProvider.attachNetwork] turns the
/// result into the app's HTTP client response. Attached on the first `mockApi` / `offline`, detached when the run ends.
class _NetworkMock {
  final _mocks = <_ApiMock>[];
  bool _offline = false;
  bool _attached = false;

  set offline(bool v) {
    _attach();
    _offline = v;
  }

  void add(_ApiMock m) {
    _attach();
    _mocks.insert(0, m); // the newest mock wins
  }

  void reset() {
    _mocks.clear();
    _offline = false;
  }

  void _attach() {
    if (_attached) return;
    Bist.instance.provider.attachNetwork(_onRequest);
    _attached = true;
  }

  void close() {
    reset();
    if (_attached) Bist.instance.provider.detachNetwork();
    _attached = false;
  }

  Future<BistMockResult?> _onRequest(String method, Uri uri) async {
    if (_offline) return const BistOffline();
    final m = _mocks.where((m) => m.matches(method, uri)).firstOrNull;
    if (m == null) return null;
    if (m.times != null) {
      m.times = m.times! - 1;
      if (m.times! <= 0) _mocks.remove(m);
    }
    if (m.delay != null && m.delay! > 0) await Future<void>.delayed(Duration(milliseconds: m.delay!));
    return BistMockResponse(m.status, m.body ?? '{}', message: m.status >= 400 ? serverMessage(m.body) : null);
  }

  /// Message in an error body (`message` / `Message` / `error` / `title`), or the body itself when it is plain text
  static String? serverMessage(String? body) {
    if (body == null || body.trim().isEmpty) return null;
    try {
      final j = jsonDecode(body);
      if (j is Map) {
        for (final k in const ['message', 'Message', 'error', 'title']) {
          if (j[k] is String && (j[k] as String).isNotEmpty) return j[k] as String;
        }
      }
      return null;
    } on FormatException {
      return body;
    }
  }
}
