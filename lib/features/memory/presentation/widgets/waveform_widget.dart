import 'package:flutter/material.dart';

class WaveformWidget extends StatelessWidget {
  final List<double> amplitudes;
  final Color color;
  final double width;
  final double height;

  const WaveformWidget({
    super.key,
    required this.amplitudes,
    required this.color,
    this.width = 56,
    this.height = 28,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _WaveformPainter(amplitudes: amplitudes, color: color),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> amplitudes;
  final Color color;

  _WaveformPainter({required this.amplitudes, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (amplitudes.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.0;

    final count = amplitudes.length;
    final spacing = size.width / count;
    const minH = 4.0;

    for (int i = 0; i < count; i++) {
      final x = spacing * i + spacing / 2;
      final barH = minH + amplitudes[i] * (size.height - minH);
      final top = (size.height - barH) / 2;
      canvas.drawLine(Offset(x, top), Offset(x, top + barH), paint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) => true;
}
