import 'package:flutter/material.dart';

class HsvSaturationValuePainter extends CustomPainter {
  final double hue;
  final double saturation;
  final double value;

  HsvSaturationValuePainter(this.hue, this.saturation, this.value);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    final saturationGradient = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        Colors.white,
        HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor(),
      ],
    );
    canvas.drawRect(
        rect, Paint()..shader = saturationGradient.createShader(rect));

    final valueGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.transparent,
        Colors.black,
      ],
    );
    canvas.drawRect(rect, Paint()..shader = valueGradient.createShader(rect));

    final circleX = saturation * size.width;
    final circleY = (1.0 - value) * size.height;
    final circleColor =
        HSVColor.fromAHSV(1.0, hue, saturation, value).toColor();

    canvas.drawCircle(
      Offset(circleX, circleY),
      8,
      Paint()
        ..color = circleColor
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset(circleX, circleY),
      8,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      Offset(circleX, circleY),
      10,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(HsvSaturationValuePainter oldDelegate) {
    return oldDelegate.hue != hue ||
        oldDelegate.saturation != saturation ||
        oldDelegate.value != value;
  }
}
