import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';

class CircleCutoutPainter extends CustomPainter {
  final int cropSize;
  final Color overlayColor;

  const CircleCutoutPainter({
    required this.cropSize,
    required this.overlayColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final ui.Path path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final ui.Offset center = Offset(size.width / 2, size.height / 2);
    path.addOval(Rect.fromCircle(
      center: center,
      radius: cropSize / 2,
    ));

    path.fillType = PathFillType.evenOdd;

    final ui.Paint paint = Paint()
      ..color = overlayColor
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CircleCutoutPainter oldDelegate) {
    return oldDelegate.cropSize != cropSize ||
        oldDelegate.overlayColor != overlayColor;
  }
}