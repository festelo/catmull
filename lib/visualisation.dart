import 'package:flutter/material.dart';

class Visualisation extends StatefulWidget {
  const Visualisation({
    super.key,
    required this.animationController,
    required this.curve,
  });

  final AnimationController animationController;
  final Curve curve;

  @override
  State<Visualisation> createState() => _VisualisationState();
}

class _VisualisationState extends State<Visualisation> {
  final _scrollController = ScrollController();

  bool _repeat = false;
  bool _playing = false;
  late int _durationMs =
      widget.animationController.duration?.inMilliseconds ?? 500;

  Future<void> _play() async {
    setState(() => _playing = true);
    if (_repeat) {
      await widget.animationController.repeat();
    } else {
      widget.animationController.reset();
      await widget.animationController.forward();
    }
    setState(() => _playing = false);
  }

  Future<void> _pause() async {
    widget.animationController.stop();
    setState(() => _playing = false);
  }

  void _switchRepeat() {
    setState(() => _repeat = !_repeat);
  }

  void _changeDuration(int ms) {
    setState(() => _durationMs = ms);
    widget.animationController.duration = Duration(milliseconds: ms);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 350,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Scrollbar(
              controller: _scrollController,
              child: CustomScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(width: 48),
                        VisualisationItem(
                          name: 'translation',
                          slide: Tween(
                            begin: const Offset(0, 1),
                            end: const Offset(0, 0),
                          )
                              .chain(CurveTween(curve: widget.curve))
                              .animate(widget.animationController),
                        ),
                        const SizedBox(width: 48),
                        VisualisationItem(
                          name: 'rotation',
                          rotation: CurveTween(curve: widget.curve)
                              .animate(widget.animationController),
                        ),
                        const SizedBox(width: 48),
                        VisualisationItem(
                          name: 'scale',
                          scale: CurveTween(curve: widget.curve)
                              .animate(widget.animationController),
                        ),
                        const SizedBox(width: 48),
                        VisualisationItem(
                          name: 'opacity',
                          opacity: CurveTween(curve: widget.curve)
                              .animate(widget.animationController),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),
          Positioned(
            top: 16,
            left: 32,
            height: 48,
            child: Row(
              children: [
                IconButton.outlined(
                  icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                  onPressed: _playing ? _pause : _play,
                ),
                if (!_playing) ...[
                  const SizedBox(width: 16),
                  (_repeat ? IconButton.filled : IconButton.outlined)(
                    icon: const Icon(Icons.repeat),
                    onPressed: _switchRepeat,
                  ),
                  Slider(
                    value: _durationMs.toDouble(),
                    min: 250,
                    max: 6000,
                    onChanged: (v) => _changeDuration(v.round()),
                  ),
                  Text('${_durationMs}ms')
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class VisualisationItem extends StatelessWidget {
  const VisualisationItem({
    super.key,
    required this.name,
    this.scale,
    this.slide,
    this.rotation,
    this.opacity,
  });

  final String name;
  final Animation<double>? scale;
  final Animation<Offset>? slide;
  final Animation<double>? rotation;
  final Animation<double>? opacity;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(),
          ),
          width: 150,
          height: 150,
          alignment: Alignment.center,
          child: FadeTransition(
            opacity: opacity ?? kAlwaysCompleteAnimation,
            child: RotationTransition(
              turns: rotation ?? kAlwaysCompleteAnimation,
              child: SlideTransition(
                position: slide ?? const AlwaysStoppedAnimation(Offset.zero),
                child: ScaleTransition(
                  scale: scale ?? kAlwaysCompleteAnimation,
                  child: Container(
                    width: 25,
                    height: 25,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Text(name),
      ],
    );
  }
}
