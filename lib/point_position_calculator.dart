import 'package:catmull_rom_curve_editor/curve.dart';
import 'package:flutter/material.dart';

class PointPositionCalculator extends StatefulWidget {
  const PointPositionCalculator({
    super.key,
    required this.curve,
  });

  final WeakedCatmullRomCurve curve;

  @override
  State<PointPositionCalculator> createState() =>
      _PointPositionCalculatorState();
}

class _PointPositionCalculatorState extends State<PointPositionCalculator> {
  final TextEditingController _xController = TextEditingController();
  final TextEditingController _yController = TextEditingController();

  void _onXChanged(String value) {
    final x = double.tryParse(value);
    if (x == null || x < 0 || x > 1) {
      return;
    }
    final y = widget.curve.transform(x);
    _yController.text = y.toString();
  }

  @override
  void dispose() {
    _xController.dispose();
    _yController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 24),
        Text(
          'Enter x-coordinate to get a precise y-value on the curve',
        ),
        const SizedBox(height: 16),
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 150,
                child: TextField(
                  controller: _xController,
                  onChanged: _onXChanged,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'X coordinate',
                    hintText: 'Enter X-value',
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 150,
                child: TextField(
                  controller: _yController,
                  readOnly: true,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Y coordinate',
                    hintText: 'To be calculated',
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
