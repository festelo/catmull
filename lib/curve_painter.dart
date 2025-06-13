import 'dart:ui';

import 'package:catmull_rom_curve_editor/curve.dart';
import 'package:catmull_rom_curve_editor/utils.dart';
import 'package:flutter/material.dart';

class CurvePainter extends CustomPainter {
  CurvePainter({
    required this.curve,
    this.altCurve,
    this.points = 100000,
    this.yMax = 3,
    this.hoverHighlightedPoint,
    this.highlightedPoints = const [],
    this.dragging = false,
    this.squareSelectionStart,
    this.squareSelectionEnd,
    this.xWhereYRepeats = const [],
    this.animationValue = 0,
    this.pointToCreate,
  });

  final WeakedCatmullRomCurve curve;
  final WeakedCatmullRomCurve? altCurve;
  final int points;
  final double yMax;
  final Offset? hoverHighlightedPoint;
  final List<Offset> highlightedPoints;
  final bool dragging;

  final Offset? squareSelectionStart;
  final Offset? squareSelectionEnd;
  final List<double> xWhereYRepeats;
  final double animationValue;

  final Offset? pointToCreate;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      getGridLinesPath(size),
      Paint()
        ..color = Colors.grey
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    if (altCurve != null) {
      canvas
        ..drawPath(
          getLinePath(size, curve: altCurve!),
          Paint()
            ..color = Colors.red.withOpacity(0.8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        )
        ..drawPath(
          getPointsPath(size, curve: altCurve!),
          Paint()..color = Colors.orange.withOpacity(0.8),
        );
    }

    canvas
      ..drawPath(
        getLinePath(size, curve: curve),
        Paint()
          ..color = Colors.black
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      )
      ..drawPath(
        getPointsPath(size, curve: curve),
        Paint()..color = Colors.blueGrey,
      );

    final squareSelectionPath = getSquareSelectionPath(size);
    if (squareSelectionPath != null) {
      canvas.drawPath(
        squareSelectionPath,
        Paint()..color = Colors.lightBlue.withOpacity(0.1),
      );
    }
    final highlightedPointsPath = getHighlightedPointsPath(size);
    if (highlightedPointsPath != null) {
      canvas.drawPath(
        highlightedPointsPath,
        Paint()..color = Colors.red,
      );
    }
    final hoverHighlightedPointPath = getHoverHighlightedPointPath(size);
    if (hoverHighlightedPointPath != null) {
      canvas.drawPath(
        hoverHighlightedPointPath,
        Paint()..color = Colors.red.shade700,
      );
    }
    final validationVisualisation = getValidationVisualisation(size);
    if (validationVisualisation != null) {
      canvas.drawPath(
        validationVisualisation,
        Paint()
          ..color = Colors.red.shade700.withOpacity(0.2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    final animationVisualisation = getAnimationVisualisation(size);
    if (animationVisualisation != null) {
      canvas.drawPath(
        animationVisualisation,
        Paint()
          ..color = Colors.blue.shade300
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    final highlightXPoint = getPointToCreate(size);
    if (highlightXPoint != null) {
      canvas.drawPath(
        highlightXPoint,
        Paint()..color = Colors.red.withOpacity(0.8),
      );
    }
  }

  Path getLinePath(
    Size size, {
    required WeakedCatmullRomCurve curve,
  }) {
    final path = Path();

    path.moveTo(0, size.height);

    for (var i = 0; i < 100000; i++) {
      final t = i / points;
      final offset = viewportOffsetToPixels(
        Offset(t, curve.transform(t)),
        size,
        yMax,
      );
      path.lineTo(offset.dx, offset.dy);
    }
    return path;
  }

  Path getPointsPath(
    Size size, {
    required WeakedCatmullRomCurve curve,
  }) {
    final path = Path();

    for (final point in curve.controlPoints) {
      if (highlightedPoints.contains(point)) {
        continue;
      }
      final offset = viewportOffsetToPixels(
        Offset(point.dx, point.dy),
        size,
        yMax,
      );
      path.addOval(
        Rect.fromCenter(
          center: offset,
          width: 10,
          height: 10,
        ),
      );
    }
    return path;
  }

  Path? getHighlightedPointsPath(Size size) {
    final highlightedPoints = this.highlightedPoints;
    if (highlightedPoints.isEmpty) {
      return null;
    }
    final path = Path();

    for (final point in highlightedPoints) {
      final position = viewportOffsetToPixels(
        point,
        size,
        yMax,
      );

      path.addOval(
        Rect.fromCenter(
          center: position,
          width: 12,
          height: 12,
        ),
      );
    }
    return path;
  }

  Path? getHoverHighlightedPointPath(Size size) {
    final hoverHighlightedPoint = this.hoverHighlightedPoint;
    if (hoverHighlightedPoint == null) {
      return null;
    }

    final closestPoint = viewportOffsetToPixels(
      hoverHighlightedPoint,
      size,
      yMax,
    );

    final path = Path();
    path.addOval(
      Rect.fromCenter(
        center: closestPoint,
        width: 12,
        height: 12,
      ),
    );
    return path;
  }

  Path? getSquareSelectionPath(Size size) {
    final start = squareSelectionStart;
    final end = squareSelectionEnd;
    if (start == null || end == null) {
      return null;
    }

    final path = Path();
    path.addRect(
      Rect.fromPoints(start, end),
    );
    return path;
  }

  Path getGridLinesPath(Size size) {
    final path = Path();
    final yLines = <double>[1, 2];
    for (final y in yLines) {
      final start = viewportOffsetToPixels(
        Offset(0, y),
        size,
        yMax,
      );
      final end = viewportOffsetToPixels(
        Offset(1, y),
        size,
        yMax,
      );
      path.moveTo(start.dx, start.dy);
      path.lineTo(end.dx, end.dy);
    }
    return path;
  }

  Path? getValidationVisualisation(Size size) {
    if (xWhereYRepeats.isEmpty) {
      return null;
    }
    final path = Path();
    for (final x in xWhereYRepeats) {
      final start = viewportOffsetToPixels(
        Offset(x, 0),
        size,
        yMax,
      );
      final end = viewportOffsetToPixels(
        Offset(x, 1),
        size,
        yMax,
      );
      path.moveTo(start.dx, 0);
      path.lineTo(end.dx, size.height);
    }
    return path;
  }

  Path? getAnimationVisualisation(Size size) {
    if (animationValue == 0) {
      return null;
    }
    final path = Path();
    final start = viewportOffsetToPixels(
      Offset(animationValue, 0),
      size,
      yMax,
    );
    final end = viewportOffsetToPixels(
      Offset(animationValue, 1),
      size,
      yMax,
    );
    path.moveTo(start.dx, 0);
    path.lineTo(end.dx, size.height);
    return path;
  }

  Path? getPointToCreate(Size size) {
    final pointToCreate = this.pointToCreate;

    if (pointToCreate == null) {
      return null;
    }

    return Path()
      ..addOval(
        Rect.fromCenter(center: pointToCreate, width: 12, height: 12),
      );
  }

  @override
  bool shouldRepaint(covariant CurvePainter oldDelegate) {
    return oldDelegate.curve != curve ||
        oldDelegate.points != points ||
        oldDelegate.yMax != yMax ||
        oldDelegate.highlightedPoints != highlightedPoints ||
        oldDelegate.squareSelectionStart != squareSelectionStart ||
        oldDelegate.squareSelectionEnd != squareSelectionEnd ||
        oldDelegate.animationValue != animationValue ||
        oldDelegate.pointToCreate != pointToCreate;
  }
}
