/// BIST (built-in self-test): test scripts that run **inside** your Flutter app – on a real device, a release build, in
/// front of a tester – driving the UI like a finger would.
///
/// ```dart
/// Future<void> main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await Bist.init(scriptAssets: 'assets/bist/'); // provider: MyBistProvider(); runs --dart-define=BIST_RUN_IDS=<id>
///   runApp(MaterialApp(navigatorObservers: [Bist.navigatorObserver], builder: BistPanel.overlay, home: ...));
/// }
/// ```
///
/// Scripts (`.bist` / `.json`, see `package:flutter_bist/model.dart` and `bin/editor.html`) are loaded with
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

import 'model.dart';

// Model classes only – the script builders (`tap`, `expect`, `log`…) live in `package:flutter_bist/model.dart`, so they don't
// clash with names in your app (or with `expect` of flutter_test)
export 'model.dart'
    show TestCase, TestGroup, TestSequence, TestUnit, TestAction, TestVersion, WidgetType, TextMatch, LogLevel, SwipeDirection, kTestScriptSchema;

part 'src/provider.dart';
part 'src/touch.dart';
part 'src/report.dart';
part 'src/bist.dart';
part 'src/runner.dart';
part 'src/widgets.dart';
part 'src/network.dart';
