import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../domain/zen_sim.dart';

/// Draws the zen hourglass: glass, wooden frame bars, the two sand bodies,
/// the live grain stream, and drifting dust. All simulation state lives in
/// [ZenSandSim]; this painter only samples and draws it.
class HourglassPainter extends CustomPainter {
  HourglassPainter(this.sim);
  final ZenSandSim sim;

  static const _sand = AppColors.tan;
  static const _sandDeep = AppColors.tanDeep;
  static const _glass = Color(0xFF3A4150);
  static const _frame = Color(0xFF8A7350);

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height * 0.92;
    final scale = h; // sim y ∈ [-0.5, 0.5] maps to h pixels
    final center = Offset(size.width / 2, size.height / 2);

    Offset p(double x, double y) =>
        Offset(center.dx + x * scale, center.dy + y * scale);

    // --- glass silhouette from the sim's analytic width function ---
    final left = <Offset>[];
    final right = <Offset>[];
    const steps = 60;
    for (var i = 0; i <= steps; i++) {
      final y = -0.5 + i / steps;
      final w = ZenSandSim.halfWidthAt(y);
      left.add(p(-w, y));
      right.add(p(w, y));
    }
    final glassPath = Path()
      ..addPolygon([...left, ...right.reversed], true);

    // Subtle interior tint.
    canvas.drawPath(
      glassPath,
      Paint()..color = const Color(0xFF141922).withValues(alpha: 0.6),
    );

    // --- sand: top column (rests on the neck) ---
    final f = sim.fraction;
    if (f > 0.002) {
      final surfaceY = sim.topSurfaceY;
      final dip = min(0.05, 0.02 + 0.05 * (1 - f)); // funnel toward the neck
      final wS = ZenSandSim.halfWidthAt(surfaceY) * 0.96;
      final topSand = Path()..moveTo(p(-wS, surfaceY).dx, p(-wS, surfaceY).dy);
      // Surface with a center dip.
      topSand.quadraticBezierTo(
        p(0, surfaceY + dip).dx,
        p(0, surfaceY + dip).dy,
        p(wS, surfaceY).dx,
        p(wS, surfaceY).dy,
      );
      // Down the right glass wall to the neck, across, and back up the left.
      for (var i = 0; i <= 20; i++) {
        final y = surfaceY + (0 - surfaceY) * i / 20;
        final w = ZenSandSim.halfWidthAt(y) * 0.96;
        topSand.lineTo(p(w, y).dx, p(w, y).dy);
      }
      for (var i = 20; i >= 0; i--) {
        final y = surfaceY + (0 - surfaceY) * i / 20;
        final w = ZenSandSim.halfWidthAt(y) * 0.96;
        topSand.lineTo(p(-w, y).dx, p(-w, y).dy);
      }
      topSand.close();
      canvas.drawPath(topSand, Paint()..color = _sand.withValues(alpha: 0.92));
      // Soft shading edge.
      canvas.drawPath(
        topSand,
        Paint()
          ..color = _sandDeep.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    // --- sand: bottom mound ---
    if (sim.bottomFillHeight > 0.004) {
      final mound = Path();
      const samples = 40;
      var started = false;
      for (var i = 0; i <= samples; i++) {
        final x = -ZenSandSim.maxHalfWidth +
            (2 * ZenSandSim.maxHalfWidth) * i / samples;
        final surface = sim.bottomSurfaceY(x);
        final wall = ZenSandSim.halfWidthAt(surface) * 0.98;
        final cx = x.clamp(-wall, wall);
        final pt = p(cx, surface);
        if (!started) {
          mound.moveTo(pt.dx, pt.dy);
          started = true;
        } else {
          mound.lineTo(pt.dx, pt.dy);
        }
      }
      // Close along the bottom cap: down the right wall, across, back up.
      final capW = ZenSandSim.halfWidthAt(0.498) * 0.98;
      mound.lineTo(p(capW, 0.498).dx, p(capW, 0.498).dy);
      mound.lineTo(p(-capW, 0.498).dx, p(-capW, 0.498).dy);
      mound.close();
      canvas.drawPath(mound, Paint()..color = _sand.withValues(alpha: 0.92));
      canvas.drawPath(
        mound,
        Paint()
          ..color = _sandDeep.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    // --- grain stream ---
    final grainPaint = Paint();
    for (final g in sim.grains) {
      grainPaint.color = _sand.withValues(alpha: g.alpha);
      canvas.drawCircle(p(g.x, g.y), g.size, grainPaint);
    }

    // --- dust ---
    final dustPaint = Paint()..color = Colors.white.withValues(alpha: 0.05);
    for (final d in sim.dust) {
      canvas.drawCircle(p(d.x, d.y), 1.6, dustPaint);
    }

    // --- glass outline on top of the sand ---
    canvas.drawPath(
      glassPath,
      Paint()
        ..color = _glass
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    // Faint highlight down the left side.
    canvas.drawPath(
      Path()..addPolygon(left.sublist(4, steps - 4), false),
      Paint()
        ..color = AppColors.blue.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    // --- frame bars ---
    final barW = ZenSandSim.maxHalfWidth * 2.35 * scale;
    final barH = 10.0;
    final barPaint = Paint()..color = _frame;
    for (final y in [-0.5, 0.5]) {
      final c = p(0, y);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(c.dx, c.dy + (y < 0 ? -barH / 2 : barH / 2)),
            width: barW,
            height: barH,
          ),
          const Radius.circular(5),
        ),
        barPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant HourglassPainter oldDelegate) => true;
}
