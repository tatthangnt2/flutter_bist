import 'package:flutter/material.dart';

/// BIST logo: "BIST" (Roboto Black as outlines – no font needed) on a charcoal rounded rectangle, the inside of the B filled
/// white with a green play symbol. Drawn from the paths of `icon/logo.svg` (680 × 304); keeps that aspect ratio.
class BistLogo extends StatelessWidget {
  /// Height of the logo; width = height × 680 / 304
  final double height;

  const BistLogo({super.key, this.height = 28});

  /// Width / height of the logo
  static const aspectRatio = _w / _h;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'BIST',
    image: true,
    child: CustomPaint(size: Size(height * aspectRatio, height), painter: const _LogoPainter()),
  );
}

const _w = 680.0;
const _h = 304.0;

class _LogoPainter extends CustomPainter {
  const _LogoPainter();

  static final _text = _parse(
    'M61.39 242.28L61.39 61.71L126.25 61.71Q161.1 61.71 179.27 74.49Q197.44 87.26 197.44 111.57Q197.44 125.58 190.99 135.5Q184.54 145.43 172.02 150.14Q186.15 153.86 193.72 164.03Q201.28 174.2 201.28 188.83Q201.28 215.37 184.48 228.7Q167.67 242.04 134.69 242.28ZM104.92 165.52L104.92 208.8L133.45 208.8Q145.23 208.8 151.55 203.4Q157.88 198.01 157.88 188.21Q157.88 165.64 135.43 165.52ZM104.92 136.99L127.62 136.99Q141.88 136.87 147.96 131.78Q154.03 126.7 154.03 116.78Q154.03 105.37 147.46 100.34Q140.89 95.32 126.25 95.32L104.92 95.32ZM276.94 242.28L233.53 242.28L233.53 61.71L276.94 61.71ZM405.67 194.29Q405.67 184.74 398.91 179.41Q392.15 174.07 375.16 168.37Q358.17 162.66 347.38 157.33Q312.28 140.09 312.28 109.96Q312.28 94.95 321.02 83.48Q329.77 72.01 345.77 65.62Q361.77 59.23 381.73 59.23Q401.2 59.23 416.64 66.18Q432.08 73.12 440.64 85.96Q449.2 98.79 449.2 115.29L405.79 115.29Q405.79 104.25 399.03 98.17Q392.27 92.1 380.74 92.1Q369.08 92.1 362.32 97.24Q355.56 102.39 355.56 110.33Q355.56 117.27 363.01 122.92Q370.45 128.56 389.17 134.57Q407.9 140.59 419.93 147.53Q449.2 164.4 449.2 194.04Q449.2 217.73 431.34 231.25Q413.48 244.77 382.35 244.77Q360.4 244.77 342.6 236.89Q324.81 229.01 315.82 215.31Q306.82 201.61 306.82 183.75L350.48 183.75Q350.48 198.26 357.98 205.14Q365.49 212.02 382.35 212.02Q393.14 212.02 399.41 207.37Q405.67 202.72 405.67 194.29ZM618.61 95.32L564.41 95.32L564.41 242.28L520.88 242.28L520.88 95.32L467.68 95.32L467.68 61.71L618.61 61.71Z',
  );
  static final _play = _parse(
    'M105.7 117.87C101.16 114.09 95.84 117.87 95.84 125.46L95.84 178.54C95.84 186.13 101.16 189.92 106.47 186.13L148.94 157.69C155 153.9 155 146.31 148.94 142.52Z',
  );
  static const _fills = [Rect.fromLTWH(103.43, 164.03, 55.93, 46.26), Rect.fromLTWH(103.43, 93.83, 52.09, 44.65)];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / _w, size.height / _h);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, _w, _h), const Radius.circular(46.38)), Paint()..color = const Color(0xFF202124));
    final white = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawPath(_text, white);
    for (final r in _fills) {
      canvas.drawRect(r, white);
    }
    final b = _play.getBounds();
    canvas.drawPath(
      _play,
      Paint()
        ..shader = const LinearGradient(colors: [Color(0xFF68D943), Color(0xFF159B55)], begin: Alignment.topLeft, end: Alignment.bottomRight).createShader(b),
    );
  }

  @override
  bool shouldRepaint(_LogoPainter oldDelegate) => false;
}

/// Short BIST icon: the B of the logo in a charcoal circle (`icon/icon.svg`, 128 × 128). [playOpacity] dims the green play
/// symbol (e.g. to make it blink while a script runs).
class BistIcon extends StatelessWidget {
  /// Diameter
  final double size;

  /// Opacity of the play symbol, 0..1
  final double playOpacity;

  const BistIcon({super.key, this.size = 40, this.playOpacity = 1});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'BIST',
    image: true,
    child: CustomPaint(size: Size.square(size), painter: _IconPainter(playOpacity)),
  );
}

class _IconPainter extends CustomPainter {
  final double playOpacity;

  const _IconPainter(this.playOpacity);

  static const _s = 128.0;
  static final _b = _parse(
    'M39.21 96L39.21 32L62.2 32Q74.55 32 80.99 36.53Q87.43 41.05 87.43 49.67Q87.43 54.64 85.14 58.15Q82.86 61.67 78.42 63.34Q83.43 64.66 86.11 68.26Q88.79 71.87 88.79 77.05Q88.79 86.46 82.84 91.19Q76.88 95.91 65.19 96ZM54.64 68.79L54.64 84.13L64.75 84.13Q68.92 84.13 71.16 82.22Q73.41 80.31 73.41 76.84Q73.41 68.84 65.45 68.79ZM54.64 58.68L62.68 58.68Q67.74 58.64 69.89 56.84Q72.04 55.03 72.04 51.52Q72.04 47.47 69.71 45.69Q67.38 43.91 62.2 43.91L54.64 43.91Z',
  );
  static final _play = _parse(
    'M54.91 51.9C53.3 50.56 51.42 51.9 51.42 54.59L51.42 73.41C51.42 76.1 53.3 77.44 55.18 76.1L70.24 66.02C72.39 64.67 72.39 61.98 70.24 60.64Z',
  );
  static const _fills = [Rect.fromLTWH(54.11, 68.26, 19.82, 16.4), Rect.fromLTWH(54.11, 43.38, 18.46, 15.82)];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / _s, size.height / _s);
    canvas.drawCircle(const Offset(_s / 2, _s / 2), _s / 2, Paint()..color = const Color(0xFF202124));
    final white = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawPath(_b, white);
    for (final r in _fills) {
      canvas.drawRect(r, white);
    }
    if (playOpacity <= 0) return;
    final b = _play.getBounds();
    final colors = [const Color(0xFF68D943), const Color(0xFF159B55)].map((c) => c.withValues(alpha: playOpacity.clamp(0, 1).toDouble())).toList();
    canvas.drawPath(_play, Paint()..shader = LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight).createShader(b));
  }

  @override
  bool shouldRepaint(_IconPainter oldDelegate) => oldDelegate.playOpacity != playOpacity;
}

/// SVG path data with absolute M, L, Q, C, Z only (what the logo generator writes)
Path _parse(String d) {
  final path = Path();
  final tokens = RegExp(r'[MLQCZ]|-?\d+(?:\.\d+)?').allMatches(d).map((m) => m.group(0)!).toList();
  var i = 0;
  double n() => double.parse(tokens[i++]);
  while (i < tokens.length) {
    switch (tokens[i++]) {
      case 'M':
        path.moveTo(n(), n());
      case 'L':
        path.lineTo(n(), n());
      case 'Q':
        path.quadraticBezierTo(n(), n(), n(), n());
      case 'C':
        path.cubicTo(n(), n(), n(), n(), n(), n());
      case 'Z':
        path.close();
    }
  }
  return path;
}
