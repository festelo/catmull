import 'dart:io';

import 'package:catmull_rom_curve_editor/curve_painter.dart';
import 'package:catmull_rom_curve_editor/point_position_calculator.dart';
import 'package:catmull_rom_curve_editor/tools_menu.dart';
import 'package:catmull_rom_curve_editor/utils.dart';
import 'package:catmull_rom_curve_editor/validation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'curve.dart';
import 'visualisation.dart';

void main() {
  runApp(const MyApp());
}

const selectionRadius = 15;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Catmull Rom Curve Editor',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const EditorPage(),
    );
  }
}

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _inputsTextController = TextEditingController();
  final TextEditingController _tensionTextController = TextEditingController();
  late final AnimationController _animationController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  WeakedCatmullRomCurve _curve = WeakedCatmullRomCurve(const [
    Offset(0.25, 1.15),
    Offset(0.5, 1.6),
    Offset(0.9, 0.9),
  ]);

  WeakedCatmullRomCurve? _altCurve;

  Offset? _latestHoverPoint;
  Size? _latestSize;

  List<Offset> _highlightedPoints = [];
  Offset? _hoverHighlightedPoint;
  Offset? _hoverHighlightPosition;
  List<Offset> _draggingPoints = [];
  Offset? _squareSelectionStart;
  Offset? _squareSelectionEnd;
  final yMax = 2.5;

  Offset? _pointToCreate;

  bool _isInputError = false;
  bool _isControlPressed = false;
  bool _isAltPressed = false;
  bool _dragging = false;
  bool _selecting = false;
  // something was selected
  bool _activeSelecting = false;

  List<double> xWhereYRepeats = [];
  Tool _selectedTool = Tool.animationVisualizer;

  @override
  void initState() {
    super.initState();

    _inputsTextController
      ..text = getPointsString()
      ..addListener(onTextChanged);

    HardwareKeyboard.instance.addHandler((event) {
      if (event.logicalKey == LogicalKeyboardKey.controlLeft) {
        if (event is KeyDownEvent) {
          setState(() => _isControlPressed = true);
        } else if (event is KeyUpEvent) {
          setState(() => _isControlPressed = false);
        }
        _recalculatePointToCreate();
      }
      if (event.logicalKey == LogicalKeyboardKey.altLeft) {
        if (event is KeyDownEvent) {
          setState(() {
            _isAltPressed = true;
            _altCurve = _curve;
          });
        } else if (event is KeyUpEvent) {
          setState(() {
            _isAltPressed = false;
            _altCurve = null;
          });
        }
        _recalculatePointToCreate();
      }
      return false;
    });
  }

  String getPointsString() {
    return _curve.controlPoints
        .map((e) => '${e.dx.toStringAsFixed(3)}, ${e.dy.toStringAsFixed(3)}')
        .join('\n');
  }

  String getHoverString(BoxConstraints constraints) {
    final viewportOffset = pixelsToViewportOffset(
      _hoverHighlightPosition ?? Offset.zero,
      constraints.biggest,
      yMax,
    );
    final x = viewportOffset.dx;
    final y = viewportOffset.dy;
    return '(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)})';
  }

  ({Offset point, Offset position})? findPointToHighlight(
      Offset hoverPosition, Size size) {
    final viewportHoverPoint =
        pixelsToViewportOffset(hoverPosition, size, yMax);
    final viewportClosestPoint = getClosestPoint(
      viewportHoverPoint,
      others: _curve.controlPoints,
    );

    if (viewportClosestPoint == null) {
      return null;
    }

    final closestPoint = viewportOffsetToPixels(
      viewportClosestPoint,
      size,
      yMax,
    );

    if ((closestPoint - hoverPosition).distance > selectionRadius) {
      return null;
    }

    return (
      position: closestPoint,
      point: viewportClosestPoint,
    );
  }

  void updateCurveWithPoints(List<Offset> points, {bool updateText = true}) {
    _curve = WeakedCatmullRomCurve(points, tension: _curve.tension);
    if (updateText) {
      _inputsTextController.text = getPointsString();
    }
    xWhereYRepeats = getYRepeats(points, tension: _curve.tension);
  }

  void updateCurveByString(String string, {bool updateText = true}) {
    final offsets = string.split('\n').map((e) {
      final numbers = e
          .split(',')
          .map((e) => e.trim())
          .map((e) => double.parse(e))
          .toList();
      return Offset(numbers[0], numbers[1]);
    }).toList();
    updateCurveWithPoints(offsets, updateText: updateText);
    setState(() {});
  }

  void insertPointToCurve(Offset point) {
    final newPoints = _curve.controlPoints.toList();
    final indexToInsert = newPoints.indexWhere((e) => e.dx > point.dx);
    if (indexToInsert == -1) {
      newPoints.add(point);
    } else {
      newPoints.insert(indexToInsert, point);
    }
    setState(() {
      updateCurveWithPoints(newPoints);
    });
  }

  void onTextChanged() {
    try {
      updateCurveByString(_inputsTextController.text, updateText: false);
      setState(() => _isInputError = false);
    } catch (e) {
      setState(() => _isInputError = true);
    }
  }

  void onResetText() {
    _inputsTextController.text = getPointsString();
    setState(() => _isInputError = false);
  }

  void onTensionSliderChange(double value) {
    _curve = WeakedCatmullRomCurve(_curve.controlPoints, tension: value);
    _tensionTextController.text = value.toStringAsFixed(3);
    setState(() {});
  }

  void onPanDown(Offset offset, Size size) {
    if (HardwareKeyboard.instance.isControlPressed) {
      final viewportPoint = pixelsToViewportOffset(offset, size, yMax);
      insertPointToCurve(viewportPoint);
    } else if (HardwareKeyboard.instance.isAltPressed) {
      final viewportX = pixelsToViewportOffset(
        Offset(offset.dx, 0),
        size,
        yMax,
      ).dx;

      final y = _altCurve!.transform(viewportX);
      final viewportPoint = Offset(viewportX, y);
      insertPointToCurve(viewportPoint);
    } else if (_highlightedPoints.isNotEmpty &&
        _hoverHighlightedPoint != null &&
        _highlightedPoints.contains(_hoverHighlightedPoint)) {
      setState(() {
        _dragging = true;
        _draggingPoints = _highlightedPoints;
      });
    } else if (_hoverHighlightedPoint != null) {
      setState(() {
        _dragging = true;
        _draggingPoints = [_hoverHighlightedPoint!];
      });
    } else {
      setState(() {
        _selecting = true;
        _squareSelectionStart = offset;
      });
    }
  }

  void onPanUpdate(Offset offset, Size size) {
    if (_dragging &&
        _draggingPoints.isNotEmpty &&
        _hoverHighlightedPoint != null) {
      final curvePoints = _curve.controlPoints.toList();
      final draggingPointIndexes = <int>[];
      var hoverHighlightedPointIndexOnCurve = -1;

      final hoverPointPreviousOffset = viewportOffsetToPixels(
        _hoverHighlightedPoint!,
        size,
        yMax,
      );

      for (final draggingPoint in _draggingPoints) {
        final draggingPointIndex = curvePoints.indexOf(draggingPoint);
        if (draggingPoint == _hoverHighlightedPoint) {
          hoverHighlightedPointIndexOnCurve = draggingPointIndex;
        }
        final draggingPosition = viewportOffsetToPixels(
          curvePoints[draggingPointIndex],
          size,
          yMax,
        );
        curvePoints[draggingPointIndex] = pixelsToViewportOffset(
          draggingPosition - hoverPointPreviousOffset + offset,
          size,
          yMax,
        );
        draggingPointIndexes.add(draggingPointIndex);
      }
      updateCurveWithPoints(curvePoints);
      _draggingPoints =
          draggingPointIndexes.map((i) => _curve.controlPoints[i]).toList();
      if (_highlightedPoints.isNotEmpty) {
        _highlightedPoints = _draggingPoints;
      }
      if (hoverHighlightedPointIndexOnCurve != -1) {
        _hoverHighlightedPoint =
            _curve.controlPoints[hoverHighlightedPointIndexOnCurve];
      }
      setState(() {});
    }
    final squareSelectionStart = _squareSelectionStart;
    if (_selecting && squareSelectionStart != null) {
      final squareSelectionEnd = offset;
      setState(() {
        _squareSelectionEnd = squareSelectionEnd;
      });

      final viewportRect = Rect.fromPoints(
        pixelsToViewportOffset(squareSelectionStart, size, yMax),
        pixelsToViewportOffset(squareSelectionEnd, size, yMax),
      );

      final selectedPoints =
          _curve.controlPoints.where(viewportRect.contains).toList();

      setState(() {
        _highlightedPoints = selectedPoints;
        _activeSelecting = selectedPoints.isNotEmpty;
      });
    }
  }

  void onPanUp() {
    setState(() {
      if (!_dragging) {
        _draggingPoints = [];
      }
      if (!_dragging && !_activeSelecting) {
        _highlightedPoints = [];
      }
      _dragging = false;
      _hoverHighlightedPoint = null;
      _selecting = false;
      _squareSelectionEnd = null;
      _squareSelectionStart = null;
      _activeSelecting = false;
    });
  }

  void onSecondaryPanDown(Offset offset, Size size) {
    if (_hoverHighlightedPoint != null && !_dragging) {
      final newPoints = _curve.controlPoints
          .where((e) => e != _hoverHighlightedPoint)
          .toList();
      setState(() {
        updateCurveWithPoints(newPoints);
        _highlightedPoints = _highlightedPoints
            .where((e) => e != _hoverHighlightedPoint)
            .toList();
        _hoverHighlightedPoint = null;
      });
    }
  }

  void onHover(Offset offset, Size size) {
    if (!_selecting) {
      _latestSize = size;
      _latestHoverPoint = offset;

      final pointInfo = findPointToHighlight(offset, size);
      _hoverHighlightedPoint = pointInfo?.point;

      _recalculatePointToCreate();
    }
  }

  void _recalculatePointToCreate() {
    final latestHoverPoint = _latestHoverPoint;
    final latestSize = _latestSize;
    if (latestSize == null || latestHoverPoint == null) {
      _pointToCreate = null;
      setState(() {});
      return;
    }

    final offset = latestHoverPoint;
    final size = latestSize;

    if (_isControlPressed) {
      _hoverHighlightPosition = offset;
    } else if (_isAltPressed) {
      final viewportX = pixelsToViewportOffset(
        Offset(offset.dx, 0),
        size,
        yMax,
      ).dx;

      final y = _altCurve!.transform(viewportX);

      _hoverHighlightPosition = viewportOffsetToPixels(
        Offset(viewportX, y),
        size,
        yMax,
      );
    } else {
      _hoverHighlightPosition = offset;
    }

    if (_isAltPressed || _isControlPressed) {
      _pointToCreate = _hoverHighlightPosition;
    } else {
      _pointToCreate = null;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _inputsTextController.dispose();
    _tensionTextController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inputBorder = OutlineInputBorder(
      borderSide: BorderSide(
        color: _isInputError ? Colors.red : Colors.black,
      ),
    );
    var cursor = MouseCursor.defer;

    if (_isControlPressed) {
      cursor = SystemMouseCursors.precise;
    }

    return Scaffold(
      body: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => GestureDetector(
                      onPanDown: (d) =>
                          onPanDown(d.localPosition, constraints.biggest),
                      onPanEnd: (d) => onPanUp(),
                      onPanUpdate: (d) =>
                          onPanUpdate(d.localPosition, constraints.biggest),
                      onSecondaryTapDown: (d) => onSecondaryPanDown(
                        d.localPosition,
                        constraints.biggest,
                      ),
                      child: MouseRegion(
                        cursor: cursor,
                        onHover: (e) =>
                            onHover(e.localPosition, constraints.biggest),
                        child: Stack(
                          children: [
                            AnimatedBuilder(
                              animation: _animationController,
                              builder: (context, _) => Positioned.fill(
                                child: CustomPaint(
                                  painter: CurvePainter(
                                    curve: _curve,
                                    altCurve: _altCurve,
                                    pointToCreate: _pointToCreate,
                                    hoverHighlightedPoint:
                                        _hoverHighlightedPoint,
                                    yMax: yMax,
                                    highlightedPoints: _highlightedPoints,
                                    dragging: _dragging,
                                    squareSelectionStart: _squareSelectionStart,
                                    squareSelectionEnd: _squareSelectionEnd,
                                    xWhereYRepeats: xWhereYRepeats,
                                    animationValue: _animationController.value,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 10,
                              right: 10,
                              child: Text(getHoverString(constraints)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const Divider(height: 0),
                Stack(
                  children: [
                    if (_selectedTool == Tool.animationVisualizer)
                      Visualisation(
                        animationController: _animationController,
                        curve: _curve,
                      )
                    else
                      PointPositionCalculator(
                        curve: _curve,
                      ),
                    Positioned(
                      right: 0,
                      child: ToolsMenu(
                        onToolSelected: (t) => setState(
                          () => _selectedTool = t,
                        ),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
          const VerticalDivider(width: 0),
          const SizedBox(width: 16),
          SizedBox(
            width: 250,
            height: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Points:',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    TextButton(
                      onPressed: onResetText,
                      child: const Text('Reset'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: TextField(
                    controller: _inputsTextController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: InputDecoration(
                      border: inputBorder,
                      focusedBorder: inputBorder,
                      enabledBorder: inputBorder,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Tension:',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Row(
                  children: [
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          overlayShape: SliderComponentShape.noOverlay,
                        ),
                        child: Slider(
                          value: _curve.tension,
                          onChanged: onTensionSliderChange,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 58,
                      child: TextField(
                        maxLines: 1,
                        minLines: 1,
                        controller: _tensionTextController,
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.all(8),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}
