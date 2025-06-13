import 'dart:ui';

Offset viewportOffsetToPixels(Offset offset, Size size, double yMax) {
  return Offset(
    size.width * offset.dx,
    size.height - size.height * offset.dy / yMax,
  );
}

Offset pixelsToViewportOffset(Offset offset, Size size, double yMax) {
  return Offset(
    offset.dx / size.width,
    (size.height - offset.dy) / (size.height / yMax),
  );
}

Offset? getClosestPoint(
  Offset point, {
  required List<Offset> others,
}) {
  double? minDistance;
  Offset? closestPoint;
  for (final other in others) {
    final distance = (point - other).distance;
    if (minDistance == null || distance < minDistance) {
      minDistance = distance;
      closestPoint = other;
    }
  }
  return closestPoint;
}
