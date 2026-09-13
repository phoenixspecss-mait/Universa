import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:universa/core/theme/app_colors.dart';

class TimelineStrip extends StatelessWidget {
  const TimelineStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size.fromHeight(60),
      painter: _TimelineStripPainter(),
    );
  }
}

class _TimelineStripPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paintLine = Paint()
      ..color = AppColors.border
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final centerY = size.height / 2;

    // Draw horizontal line
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), paintLine);

    // Draw time labels
    final times = ['20:00', '20:05', '20:10', '20:15', '20:20', '20:25'];
    final textStyle = GoogleFonts.jetBrainsMono(
      color: AppColors.textMuted,
      fontSize: 10,
    );

    for (int i = 0; i < times.length; i++) {
      final textSpan = TextSpan(text: times[i], style: textStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      final x = (size.width / (times.length - 1)) * i;
      textPainter.paint(canvas, Offset(x - (textPainter.width / 2), centerY + 10));
    }

    // Draw activity dots
    final paintCyan = Paint()..color = AppColors.electricCyan;
    final paintTeal = Paint()..color = AppColors.tealGreen;
    final paintAmber = Paint()..color = AppColors.rustAmber;

    // 20:14 area (approx 2.8 / 5 of the width)
    final x2014 = (size.width / 5) * 2.8;
    canvas.drawCircle(Offset(x2014 - 8, centerY), 3, paintCyan);
    canvas.drawCircle(Offset(x2014, centerY), 3, paintCyan);
    canvas.drawCircle(Offset(x2014 + 8, centerY), 3, paintCyan);

    // 20:18 area (approx 3.6 / 5)
    final x2018 = (size.width / 5) * 3.6;
    canvas.drawCircle(Offset(x2018 - 4, centerY), 3, paintTeal);
    canvas.drawCircle(Offset(x2018 + 4, centerY), 3, paintTeal);

    // 20:24 area (approx 4.8 / 5)
    final x2024 = (size.width / 5) * 4.8;
    canvas.drawCircle(Offset(x2024 - 4, centerY), 3, paintAmber);
    canvas.drawCircle(Offset(x2024 + 4, centerY), 3, paintAmber);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
