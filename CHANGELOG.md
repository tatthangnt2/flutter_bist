# Changelog

## 0.1.0

First release, split out of an in-house Flutter library.

- Script model (`package:flutter_bist/model.dart`, JSON `schema: 4`): `TestGroup` / `TestSequence` / `TestUnit`, 31 commands
  (tap, input, dates, expect / notExpect with input state, count, checked / selected, text match exact / contains / regex,
  swipe, nav, back, runTest, loops, random data, variables from screen / logs / environment, tester dialogs, mockApi /
  offline, pickFile, server).
- Runner `Bist`: real pointer and keyboard input (`BistTouch`), waits, auto-scroll, keyboard handling, reports,
  `BIST|` console lines, screenshots, `--dart-define=BIST_RUN=<id>`, writes refused on production servers.
- `BistProvider`: one class to connect an app or a UI library (screen, navigation, servers, test data, logs, network
  mocking, file picking, custom widgets); defaults work with plain Flutter.
- `BistPanel` / `BistPanel.overlay`: scripts and reports in the app.
- BIST Editor (`bin/editor.html`) and command line (`bin/bist.mjs`), sources in `tools/editor`.
