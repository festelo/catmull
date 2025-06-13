// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';

export 'dart:ui' show Offset;

/// A 2D spline that passes smoothly through the given control points using a
/// centripetal Catmull-Rom spline.
///
/// When the curve is evaluated with [transform], the output values will move
/// smoothly from one control point to the next, passing through the control
/// points.
///
/// {@template flutter.animation.WeakedCatmullRomSpline}
/// Unlike most cubic splines, Catmull-Rom splines have the advantage that their
/// curves pass through the control points given to them. They are cubic
/// polynomial representations, and, in fact, Catmull-Rom splines can be
/// converted mathematically into cubic splines. This class implements a
/// "centripetal" Catmull-Rom spline. The term centripetal implies that it won't
/// form loops or self-intersections within a single segment.
/// {@endtemplate}
///
/// See also:
///  * [Centripetal Catmull–Rom splines](https://en.wikipedia.org/wiki/Centripetal_Catmull%E2%80%93Rom_spline)
///    on Wikipedia.
///  * [Parameterization and Applications of Catmull-Rom Curves](http://faculty.cs.tamu.edu/schaefer/research/cr_cad.pdf),
///    a paper on using Catmull-Rom splines.
///  * [WeakedCatmullRomCurve], an animation curve that uses a [WeakedCatmullRomSpline] as its
///    internal representation.
class WeakedCatmullRomSpline extends Curve2D {
  /// Constructs a centripetal Catmull-Rom spline curve.
  ///
  /// The `controlPoints` argument is a list of four or more points that
  /// describe the points that the curve must pass through.
  ///
  /// The optional `tension` argument controls how tightly the curve approaches
  /// the given `controlPoints`. It must be in the range 0.0 to 1.0, inclusive. It
  /// defaults to 0.0, which provides the smoothest curve. A value of 1.0
  /// produces a linear interpolation between points.
  ///
  /// The optional `endHandle` and `startHandle` points are the beginning and
  /// ending handle positions. If not specified, they are created automatically
  /// by extending the line formed by the first and/or last line segment in the
  /// `controlPoints`, respectively. The spline will not go through these handle
  /// points, but they will affect the slope of the line at the beginning and
  /// end of the spline. The spline will attempt to match the slope of the line
  /// formed by the start or end handle and the neighboring first or last
  /// control point. The default is chosen so that the slope of the line at the
  /// ends matches that of the first or last line segment in the control points.
  ///
  /// The `controlPoints` list must contain at least four control points to
  /// interpolate.
  ///
  /// The internal curve data structures are lazily computed the first time
  /// [transform] is called. If you would rather pre-compute the structures,
  /// use [WeakedCatmullRomSpline.precompute] instead.
  WeakedCatmullRomSpline(
    List<Offset> controlPoints, {
    double tension = 0.0,
    Offset? startHandle,
    Offset? endHandle,
  })  : assert(
            tension <= 1.0, 'tension $tension must not be greater than 1.0.'),
        assert(tension >= 0.0, 'tension $tension must not be negative.'),
        assert(controlPoints.length > 3,
            'There must be at least four control points to create a WeakedCatmullRomSpline.'),
        _controlPoints = controlPoints,
        _startHandle = startHandle,
        _endHandle = endHandle,
        _tension = tension,
        _cubicSegments = <List<Offset>>[];

  /// Constructs a centripetal Catmull-Rom spline curve.
  ///
  /// The same as [WeakedCatmullRomSpline.new], except that the internal data
  /// structures are precomputed instead of being computed lazily.
  WeakedCatmullRomSpline.precompute(
    List<Offset> controlPoints, {
    double tension = 0.0,
    Offset? startHandle,
    Offset? endHandle,
  })  : assert(
            tension <= 1.0, 'tension $tension must not be greater than 1.0.'),
        assert(tension >= 0.0, 'tension $tension must not be negative.'),
        assert(controlPoints.length > 3,
            'There must be at least four control points to create a WeakedCatmullRomSpline.'),
        _controlPoints = null,
        _startHandle = null,
        _endHandle = null,
        _tension = null,
        _cubicSegments = _computeSegments(controlPoints, tension,
            startHandle: startHandle, endHandle: endHandle);

  static List<List<Offset>> _computeSegments(
    List<Offset> controlPoints,
    double tension, {
    Offset? startHandle,
    Offset? endHandle,
  }) {
    assert(
        startHandle == null || startHandle.isFinite,
        'The provided startHandle of WeakedCatmullRomSpline must be finite. The '
        'startHandle given was $startHandle.');
    assert(
        endHandle == null || endHandle.isFinite,
        'The provided endHandle of WeakedCatmullRomSpline must be finite. The endHandle '
        'given was $endHandle.');
    assert(() {
      for (int index = 0; index < controlPoints.length; index++) {
        if (!controlPoints[index].isFinite) {
          throw FlutterError(
              'The provided WeakedCatmullRomSpline control point at index $index is not '
              'finite. The control point given was ${controlPoints[index]}.');
        }
      }
      return true;
    }());
    // If not specified, select the first and last control points (which are
    // handles: they are not intersected by the resulting curve) so that they
    // extend the first and last segments, respectively.
    startHandle ??= controlPoints[0] * 2.0 - controlPoints[1];
    endHandle ??=
        controlPoints.last * 2.0 - controlPoints[controlPoints.length - 2];
    final List<Offset> allPoints = <Offset>[
      startHandle,
      ...controlPoints,
      endHandle,
    ];

    // An alpha of 0.5 is what makes it a centripetal Catmull-Rom spline. A
    // value of 0.0 would make it a uniform Catmull-Rom spline, and a value of
    // 1.0 would make it a chordal Catmull-Rom spline. Non-centripetal values
    // for alpha can give self-intersecting behavior or looping within a
    // segment.
    const double alpha = 0.5;
    final double reverseTension = 1.0 - tension;
    final List<List<Offset>> result = <List<Offset>>[];
    for (int i = 0; i < allPoints.length - 3; ++i) {
      final List<Offset> curve = <Offset>[
        allPoints[i],
        allPoints[i + 1],
        allPoints[i + 2],
        allPoints[i + 3]
      ];
      final Offset diffCurve10 = curve[1] - curve[0];
      final Offset diffCurve21 = curve[2] - curve[1];
      final Offset diffCurve32 = curve[3] - curve[2];
      final double t01 = math.pow(diffCurve10.distance, alpha).toDouble();
      final double t12 = math.pow(diffCurve21.distance, alpha).toDouble();
      final double t23 = math.pow(diffCurve32.distance, alpha).toDouble();

      final Offset m1 = (diffCurve21 +
              (diffCurve10 / t01 - (curve[2] - curve[0]) / (t01 + t12)) * t12) *
          reverseTension;
      final Offset m2 = (diffCurve21 +
              (diffCurve32 / t23 - (curve[3] - curve[1]) / (t12 + t23)) * t12) *
          reverseTension;
      final Offset sumM12 = m1 + m2;

      final List<Offset> segment = <Offset>[
        diffCurve21 * -2.0 + sumM12,
        diffCurve21 * 3.0 - m1 - sumM12,
        m1,
        curve[1],
      ];
      result.add(segment);
    }
    return result;
  }

  // The list of control point lists for each cubic segment of the spline.
  final List<List<Offset>> _cubicSegments;

  // This is non-empty only if the _cubicSegments are being computed lazily.
  final List<Offset>? _controlPoints;
  final Offset? _startHandle;
  final Offset? _endHandle;
  final double? _tension;

  void _initializeIfNeeded() {
    if (_cubicSegments.isNotEmpty) {
      return;
    }
    _cubicSegments.addAll(
      _computeSegments(_controlPoints!, _tension!,
          startHandle: _startHandle, endHandle: _endHandle),
    );
  }

  @override
  @protected
  int get samplingSeed {
    _initializeIfNeeded();
    final Offset seedPoint = _cubicSegments[0][1];
    return ((seedPoint.dx + seedPoint.dy) * 10000).round();
  }

  @override
  Offset transformInternal(double t) {
    _initializeIfNeeded();
    final double length = _cubicSegments.length.toDouble();
    final double position;
    final double localT;
    final int index;
    if (t < 1.0) {
      position = t * length;
      localT = position % 1.0;
      index = position.floor();
    } else {
      position = length;
      localT = 1.0;
      index = _cubicSegments.length - 1;
    }
    final List<Offset> cubicControlPoints = _cubicSegments[index];
    final double localT2 = localT * localT;
    return cubicControlPoints[0] * localT2 * localT +
        cubicControlPoints[1] * localT2 +
        cubicControlPoints[2] * localT +
        cubicControlPoints[3];
  }
}

/// An animation easing curve that passes smoothly through the given control
/// points using a centripetal Catmull-Rom spline.
///
/// When this curve is evaluated with [transform], the values will interpolate
/// smoothly from one control point to the next, passing through (0.0, 0.0), the
/// given points, and then (1.0, 1.0).
///
/// {@macro flutter.animation.WeakedCatmullRomSpline}
///
/// This class uses a centripetal Catmull-Rom curve (a [WeakedCatmullRomSpline]) as
/// its internal representation. The term centripetal implies that it won't form
/// loops or self-intersections within a single segment, and corresponds to a
/// Catmull-Rom α (alpha) value of 0.5.
///
/// See also:
///
///  * [WeakedCatmullRomSpline], the 2D spline that this curve uses to generate its values.
///  * A Wikipedia article on [centripetal Catmull-Rom splines](https://en.wikipedia.org/wiki/Centripetal_Catmull%E2%80%93Rom_spline).
///  * [WeakedCatmullRomCurve.new] for a description of the constraints put on the
///    input control points.
///  * This [paper on using Catmull-Rom splines](http://faculty.cs.tamu.edu/schaefer/research/cr_cad.pdf).
class WeakedCatmullRomCurve extends Curve {
  /// Constructs a centripetal [WeakedCatmullRomCurve].
  ///
  /// It takes a list of two or more points that describe the points that the
  /// curve must pass through. See [controlPoints] for a description of the
  /// restrictions placed on control points. In addition to the given
  /// [controlPoints], the curve will begin with an implicit control point at
  /// (0.0, 0.0) and end with an implicit control point at (1.0, 1.0), so that
  /// the curve begins and ends at those points.
  ///
  /// The optional [tension] argument controls how tightly the curve approaches
  /// the given `controlPoints`. It must be in the range 0.0 to 1.0, inclusive. It
  /// defaults to 0.0, which provides the smoothest curve. A value of 1.0
  /// is equivalent to a linear interpolation between points.
  ///
  /// The internal curve data structures are lazily computed the first time
  /// [transform] is called. If you would rather pre-compute the curve, use
  /// [WeakedCatmullRomCurve.precompute] instead.
  ///
  /// See also:
  ///
  ///  * This [paper on using Catmull-Rom splines](http://faculty.cs.tamu.edu/schaefer/research/cr_cad.pdf).
  WeakedCatmullRomCurve(this.controlPoints, {this.tension = 0.0})
      :
        // Pre-compute samples so that we don't have to evaluate the spline's inverse
        // all the time in transformInternal.
        _precomputedSamples = <Curve2DSample>[];

  /// Constructs a centripetal [WeakedCatmullRomCurve].
  ///
  /// Same as [WeakedCatmullRomCurve.new], but it precomputes the internal curve data
  /// structures for a more predictable computation load.
  WeakedCatmullRomCurve.precompute(this.controlPoints, {this.tension = 0.0})
      :
        // Pre-compute samples so that we don't have to evaluate the spline's inverse
        // all the time in transformInternal.
        _precomputedSamples = _computeSamples(controlPoints, tension);

  static List<Curve2DSample> _computeSamples(
      List<Offset> controlPoints, double tension) {
    return WeakedCatmullRomSpline.precompute(
      // Force the first and last control points for the spline to be (0, 0)
      // and (1, 1), respectively.
      <Offset>[Offset.zero, ...controlPoints, const Offset(1.0, 1.0)],
      tension: tension,
    ).generateSamples(tolerance: 1e-12).toList();
  }

  /// A static accumulator for assertion failures. Not used in release mode.
  static final List<String> _debugAssertReasons = <String>[];

  // The precomputed approximation curve, so that evaluation of the curve is
  // efficient.
  //
  // If the curve is constructed lazily, then this will be empty, and will be filled
  // the first time transform is called.
  final List<Curve2DSample> _precomputedSamples;

  /// The control points used to create this curve.
  ///
  /// The `dx` value of each [Offset] in [controlPoints] represents the
  /// animation value at which the curve should pass through the `dy` value of
  /// the same control point.
  ///
  /// The [controlPoints] list must meet the following criteria:
  ///
  ///  * The list must contain at least two points.
  ///  * The X value of each point must be greater than 0.0 and less then 1.0.
  ///  * The X values of each point must be greater than the
  ///    previous point's X value (i.e. monotonically increasing). The Y values
  ///    are not constrained.
  ///  * The resulting spline must be single-valued in X. That is, for each X
  ///    value, there must be exactly one Y value. This means that the control
  ///    points must not generated a spline that loops or overlaps itself.
  ///
  /// The static function [validateControlPoints] can be used to check that
  /// these conditions are met, and will return true if they are. In debug mode,
  /// it will also optionally return a list of reasons in text form. In debug
  /// mode, the constructor will assert that these conditions are met and print
  /// the reasons if the assert fires.
  ///
  /// When the curve is evaluated with [transform], the values will interpolate
  /// smoothly from one control point to the next, passing through (0.0, 0.0), the
  /// given control points, and (1.0, 1.0).
  final List<Offset> controlPoints;

  /// The "tension" of the curve.
  ///
  /// The [tension] attribute controls how tightly the curve approaches the
  /// given [controlPoints]. It must be in the range 0.0 to 1.0, inclusive. It
  /// is optional, and defaults to 0.0, which provides the smoothest curve. A
  /// value of 1.0 is equivalent to a linear interpolation between control
  /// points.
  final double tension;

  /// Validates that a given set of control points for a [WeakedCatmullRomCurve] is
  /// well-formed and will not produce a spline that self-intersects.
  ///
  /// This method is also used in debug mode to validate a curve to make sure
  /// that it won't violate the contract for the [WeakedCatmullRomCurve.new]
  /// constructor.
  ///
  /// If in debug mode, and `reasons` is non-null, this function will fill in
  /// `reasons` with descriptions of the problems encountered. The `reasons`
  /// argument is ignored in release mode.
  ///
  /// In release mode, this function can be used to decide if a proposed
  /// modification to the curve will result in a valid curve.
  static bool validateControlPoints(
    List<Offset>? controlPoints, {
    double tension = 0.0,
    List<String>? reasons,
  }) {
    if (controlPoints == null) {
      assert(() {
        reasons?.add('Supplied control points cannot be null');
        return true;
      }());
      return false;
    }

    if (controlPoints.length < 2) {
      assert(() {
        reasons?.add(
            'There must be at least two points supplied to create a valid curve.');
        return true;
      }());
      return false;
    }

    controlPoints = <Offset>[
      Offset.zero,
      ...controlPoints,
      const Offset(1.0, 1.0)
    ];
    final Offset startHandle = controlPoints[0] * 2.0 - controlPoints[1];
    final Offset endHandle =
        controlPoints.last * 2.0 - controlPoints[controlPoints.length - 2];
    controlPoints = <Offset>[startHandle, ...controlPoints, endHandle];
    double lastX = -double.infinity;
    for (int i = 0; i < controlPoints.length; ++i) {
      if (i > 1 &&
          i < controlPoints.length - 2 &&
          (controlPoints[i].dx <= 0.0 || controlPoints[i].dx >= 1.0)) {
        assert(() {
          reasons?.add(
            'Control points must have X values between 0.0 and 1.0, exclusive. '
            'Point $i has an x value (${controlPoints![i].dx}) which is outside the range.',
          );
          return true;
        }());
        return false;
      }
      if (controlPoints[i].dx <= lastX) {
        assert(() {
          reasons?.add(
            'Each X coordinate must be greater than the preceding X coordinate '
            '(i.e. must be monotonically increasing in X). Point $i has an x value of '
            '${controlPoints![i].dx}, which is not greater than $lastX',
          );
          return true;
        }());
        return false;
      }
      lastX = controlPoints[i].dx;
    }

    bool success = true;

    // An empirical test to make sure things are single-valued in X.
    lastX = -double.infinity;
    const double tolerance = 1e-3;
    final WeakedCatmullRomSpline testSpline =
        WeakedCatmullRomSpline(controlPoints, tension: tension);
    final double start = testSpline.findInverse(0.0);
    final double end = testSpline.findInverse(1.0);
    final Iterable<Curve2DSample> samplePoints =
        testSpline.generateSamples(start: start, end: end);

    /// If the first and last points in the samples aren't at (0,0) or (1,1)
    /// respectively, then the curve is multi-valued at the ends.
    if (samplePoints.first.value.dy.abs() > tolerance ||
        (1.0 - samplePoints.last.value.dy).abs() > tolerance) {
      bool bail = true;
      success = false;
      assert(() {
        reasons?.add(
          'The curve has more than one Y value at X = ${samplePoints.first.value.dx}. '
          'Try moving some control points further away from this value of X, or increasing '
          'the tension.',
        );
        // No need to keep going if we're not giving reasons.
        bail = reasons == null;
        return true;
      }());
      if (bail) {
        // If we're not in debug mode, then we want to bail immediately
        // instead of checking everything else.
        return false;
      }
    }
    for (final Curve2DSample sample in samplePoints) {
      final Offset point = sample.value;
      final double t = sample.t;
      final double x = point.dx;
      if (t >= start && t <= end && (x < -1e-3 || x > 1.0 + 1e-3)) {
        bool bail = true;
        success = false;
        assert(() {
          reasons?.add(
            'The resulting curve has an X value ($x) which is outside '
            'the range [0.0, 1.0], inclusive.',
          );
          // No need to keep going if we're not giving reasons.
          bail = reasons == null;
          return true;
        }());
        if (bail) {
          // If we're not in debug mode, then we want to bail immediately
          // instead of checking all the segments.
          return false;
        }
      }
      if (x < lastX) {
        bool bail = true;
        success = false;
        assert(() {
          reasons?.add(
            'The curve has more than one Y value at x = $x. Try moving '
            'some control points further apart in X, or increasing the tension.',
          );
          // No need to keep going if we're not giving reasons.
          bail = reasons == null;
          return true;
        }());
        if (bail) {
          // If we're not in debug mode, then we want to bail immediately
          // instead of checking all the segments.
          return false;
        }
      }
      lastX = x;
    }
    return success;
  }

  static bool validateControlPoint(
    List<Offset>? controlPoints, {
    double tension = 0.0,
    List<String>? reasons,
  }) {
    if (controlPoints == null) {
      assert(() {
        reasons?.add('Supplied control points cannot be null');
        return true;
      }());
      return false;
    }

    if (controlPoints.length < 2) {
      assert(() {
        reasons?.add(
            'There must be at least two points supplied to create a valid curve.');
        return true;
      }());
      return false;
    }

    controlPoints = <Offset>[
      Offset.zero,
      ...controlPoints,
      const Offset(1.0, 1.0)
    ];
    final Offset startHandle = controlPoints[0] * 2.0 - controlPoints[1];
    final Offset endHandle =
        controlPoints.last * 2.0 - controlPoints[controlPoints.length - 2];
    controlPoints = <Offset>[startHandle, ...controlPoints, endHandle];
    double lastX = -double.infinity;
    for (int i = 0; i < controlPoints.length; ++i) {
      if (i > 1 &&
          i < controlPoints.length - 2 &&
          (controlPoints[i].dx <= 0.0 || controlPoints[i].dx >= 1.0)) {
        assert(() {
          reasons?.add(
            'Control points must have X values between 0.0 and 1.0, exclusive. '
            'Point $i has an x value (${controlPoints![i].dx}) which is outside the range.',
          );
          return true;
        }());
        return false;
      }
      if (controlPoints[i].dx <= lastX) {
        assert(() {
          reasons?.add(
            'Each X coordinate must be greater than the preceding X coordinate '
            '(i.e. must be monotonically increasing in X). Point $i has an x value of '
            '${controlPoints![i].dx}, which is not greater than $lastX',
          );
          return true;
        }());
        return false;
      }
      lastX = controlPoints[i].dx;
    }

    bool success = true;

    // An empirical test to make sure things are single-valued in X.
    lastX = -double.infinity;
    const double tolerance = 1e-3;
    final WeakedCatmullRomSpline testSpline =
        WeakedCatmullRomSpline(controlPoints, tension: tension);
    final double start = testSpline.findInverse(0.0);
    final double end = testSpline.findInverse(1.0);
    final Iterable<Curve2DSample> samplePoints =
        testSpline.generateSamples(start: start, end: end);

    /// If the first and last points in the samples aren't at (0,0) or (1,1)
    /// respectively, then the curve is multi-valued at the ends.
    if (samplePoints.first.value.dy.abs() > tolerance ||
        (1.0 - samplePoints.last.value.dy).abs() > tolerance) {
      bool bail = true;
      success = false;
      assert(() {
        reasons?.add(
          'The curve has more than one Y value at X = ${samplePoints.first.value.dx}. '
          'Try moving some control points further away from this value of X, or increasing '
          'the tension.',
        );
        // No need to keep going if we're not giving reasons.
        bail = reasons == null;
        return true;
      }());
      if (bail) {
        // If we're not in debug mode, then we want to bail immediately
        // instead of checking everything else.
        return false;
      }
    }
    for (final Curve2DSample sample in samplePoints) {
      final Offset point = sample.value;
      final double t = sample.t;
      final double x = point.dx;
      if (t >= start && t <= end && (x < -1e-3 || x > 1.0 + 1e-3)) {
        bool bail = true;
        success = false;
        assert(() {
          reasons?.add(
            'The resulting curve has an X value ($x) which is outside '
            'the range [0.0, 1.0], inclusive.',
          );
          // No need to keep going if we're not giving reasons.
          bail = reasons == null;
          return true;
        }());
        if (bail) {
          // If we're not in debug mode, then we want to bail immediately
          // instead of checking all the segments.
          return false;
        }
      }
      if (x < lastX) {
        bool bail = true;
        success = false;
        assert(() {
          reasons?.add(
            'The curve has more than one Y value at x = $x. Try moving '
            'some control points further apart in X, or increasing the tension.',
          );
          // No need to keep going if we're not giving reasons.
          bail = reasons == null;
          return true;
        }());
        if (bail) {
          // If we're not in debug mode, then we want to bail immediately
          // instead of checking all the segments.
          return false;
        }
      }
      lastX = x;
    }
    return success;
  }

  @override
  double transformInternal(double t) {
    // Linearly interpolate between the two closest samples generated when the
    // curve was created.
    if (_precomputedSamples.isEmpty) {
      // Compute the samples now if we were constructed lazily.
      _precomputedSamples.addAll(_computeSamples(controlPoints, tension));
    }
    int start = 0;
    int end = _precomputedSamples.length - 1;
    int mid;
    Offset value;
    Offset startValue = _precomputedSamples[start].value;
    Offset endValue = _precomputedSamples[end].value;
    // Use a binary search to find the index of the sample point that is just
    // before t.
    while (end - start > 1) {
      mid = (end + start) ~/ 2;
      value = _precomputedSamples[mid].value;
      if (t >= value.dx) {
        start = mid;
        startValue = value;
      } else {
        end = mid;
        endValue = value;
      }
    }

    // Now interpolate between the found sample and the next one.
    final double t2 = (t - startValue.dx) / (endValue.dx - startValue.dx);
    return lerpDouble(startValue.dy, endValue.dy, t2)!;
  }
}
