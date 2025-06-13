import 'package:flutter/widgets.dart';

class CurveValidationFailure {}

List<double> getYRepeats(
  List<Offset> controlPoints, {
  double tension = 0.0,
}) {
  controlPoints = <Offset>[
    Offset.zero,
    ...controlPoints,
    const Offset(1.0, 1.0)
  ];

  // An empirical test to make sure things are single-valued in X.
  var lastX = -double.infinity;
  final testSpline = CatmullRomSpline(controlPoints, tension: tension);
  final double start = testSpline.findInverse(0.0);
  final double end = testSpline.findInverse(1.0);
  final Iterable<Curve2DSample> samplePoints =
      testSpline.generateSamples(start: start, end: end);

  final List<double> xOffsetsWithRepetition = [];

  for (final Curve2DSample sample in samplePoints) {
    final Offset point = sample.value;
    final double x = point.dx;
    if (x < lastX) {
      xOffsetsWithRepetition.add(x);
    }
    lastX = x;
  }
  return xOffsetsWithRepetition;
}
