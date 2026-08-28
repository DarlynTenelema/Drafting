import 'package:flutter/material.dart';

class AnimatedAppIcon extends StatefulWidget {
  final String outlineImage;
  final String solidImage;
  final double width;
  final double height;
  final bool isActive;
  final Duration duration;

  const AnimatedAppIcon({
    super.key,
    required this.outlineImage,
    required this.solidImage,
    this.width = 24,
    this.height = 24,
    this.isActive = false,
    this.duration = const Duration(milliseconds: 300),
  });

  @override
  State<AnimatedAppIcon> createState() => _AnimatedAppIconState();
}

class _AnimatedAppIconState extends State<AnimatedAppIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    
    // Animación de rebote (pop) cuando se activa
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.15).chain(CurveTween(curve: Curves.easeOutCubic)), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0).chain(CurveTween(curve: Curves.easeInCubic)), weight: 50),
    ]).animate(_controller);
    
    if (widget.isActive) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(AnimatedAppIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _controller.forward(from: 0.0);
      } else {
        // Cuando se desactiva no hacemos rebote, solo cross-fade
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: AnimatedCrossFade(
        firstChild: Image.asset(widget.outlineImage, width: widget.width, height: widget.height),
        secondChild: Image.asset(widget.solidImage, width: widget.width, height: widget.height),
        crossFadeState: widget.isActive ? CrossFadeState.showSecond : CrossFadeState.showFirst,
        duration: widget.duration,
      ),
    );
  }
}
