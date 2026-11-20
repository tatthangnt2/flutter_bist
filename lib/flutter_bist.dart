/// BIST (built-in self-test): test scripts that run **inside** your Flutter app – on a real device, a release build, in
/// front of a tester – driving the UI like a finger would.
///
/// ```dart
/// Future<void> main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await Bist.init(scriptAssets: 'assets/bist/'); // provider: MyBistProvider(); runs --dart-define=BIST_RUN_IDS=<id>
///   runApp(MaterialApp(navigatorObservers: [Bist.navigatorObserver], builder: BistView.overlay, home: ...));
/// }
/// ```
///
/// Scripts (`.bist` / `.json`, see the script model below and `bin/editor.html`) are loaded with
/// [Bist.init] (`scriptAssets:`), [Bist.add] / [Bist.loadAssets] and run with [Bist.run] or `--dart-define=BIST_RUN_IDS=<id>`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'src/unit.dart';

// Everything is exported from this library: script model and builders (`tap`, `expect`, `log`…), the UI (`BistView`,
// `BistLogo`, `BistIcon`, `BistLocalizations`). Test files that also import flutter_test:
// `import 'package:flutter_bist/flutter_bist.dart' hide expect;` (or a prefix: `as bist` → `bist.expect(...)`).
export 'src/unit.dart';
export 'src/bist_view.dart';

part 'src/provider.dart';
part 'src/touch.dart';
part 'src/result.dart';
part 'src/bist.dart';
part 'src/executor.dart';
part 'src/widgets.dart';
part 'src/network.dart';
