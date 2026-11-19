import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_bist/flutter_bist.dart' hide expect;
import 'package:flutter_bist/flutter_bist.dart' as b;
import 'package:flutter_test/flutter_test.dart';

/// Bist.init: provider, scripts from assets, BIST_RUN_IDS auto-run
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String script(String id) => TestGroup(
    id: id,
    name: id,
    cases: [
      TestUnit(name: 'a', steps: [b.wait(1)]),
    ],
  ).encode();

  setUp(() => Bist.instance.clear());

  test('loads *.bist / *.json under scriptAssets, sets the provider', () async {
    final provider = BistProvider();
    final bundle = _Bundle({
      'assets/bist/b.bist': script('b'),
      'assets/bist/a.json': script('a'),
      'assets/bist/readme.txt': 'not a script',
      'assets/other/c.json': script('c'),
      'assets/bist/bad.json': '{',
    });
    final count = await Bist.init(provider: provider, scriptAssets: 'assets/bist/', bundle: bundle);
    expect(count, 2);
    expect(Bist.instance.provider, same(provider));
    expect(Bist.instance.scripts.map((e) => e.id), ['a', 'b']); // sorted by file name
  });

  test('no scriptAssets: loads nothing, default provider', () async {
    final count = await Bist.init(dartDefine: false);
    expect(count, 0);
    expect(Bist.instance.scripts, isEmpty);
    expect(Bist.instance.provider.runtimeType, BistProvider);
  });
}

/// Asset bundle with an AssetManifest.bin listing [files]
class _Bundle extends CachingAssetBundle {
  _Bundle(this.files);

  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage({
        for (final f in files.keys)
          f: [
            {'asset': f},
          ],
      })!;
    }
    final s = files[key];
    if (s == null) throw StateError('No asset $key');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(s)));
  }
}
