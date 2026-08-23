import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'events.dart';
import 'render_target.dart';

/// A Flutter widget that displays a software-rendered Slint component with
/// pointer and keyboard input handling.
///
/// Backend-agnostic: works with any [SlintSoftwareRenderTarget] — the
/// interpreter path (`slint_interpreter`) or the compiled path (`slint_compiler`).
///
/// Example:
/// ```dart
/// SlintView(target: component.renderTarget)
/// ```
class SlintView extends StatefulWidget {
  const SlintView({super.key, required this.target});

  final SlintSoftwareRenderTarget target;

  @override
  State<SlintView> createState() => _SlintViewState();
}

class _SlintViewState extends State<SlintView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final FocusNode _focusNode = FocusNode();
  ui.Image? _image;
  bool _decoding = false;
  double _dpr = 1;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    if (_decoding) return;
    if (widget.target.render() || _image == null) {
      _decodeImage();
    }
  }

  void _decodeImage() {
    final target = widget.target;
    final w = target.width;
    final h = target.height;
    if (w <= 0 || h <= 0) return;

    _decoding = true;
    try {
      ui.decodeImageFromPixels(
        _unpremultiplyCopy(target.pixels),
        w,
        h,
        ui.PixelFormat.rgba8888,
        (image) {
          if (!mounted) {
            image.dispose();
            _decoding = false;
            return;
          }
          _image?.dispose();
          setState(() {
            _image = image;
            _decoding = false;
          });
        },
      );
    } catch (_) {
      _decoding = false;
      rethrow;
    }
  }

  /// Slint software frames are premultiplied; Flutter's rgba8888 is straight.
  Uint8List _unpremultiplyCopy(Uint8List src) {
    final out = Uint8List.fromList(src);
    for (var i = 0; i + 3 < out.length; i += 4) {
      final a = out[i + 3];
      if (a == 0 || a == 255) {
        continue;
      }
      out[i] = (out[i] * 255 / a).round().clamp(0, 255);
      out[i + 1] = (out[i + 1] * 255 / a).round().clamp(0, 255);
      out[i + 2] = (out[i + 2] * 255 / a).round().clamp(0, 255);
    }
    return out;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focusNode.dispose();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _dpr = MediaQuery.devicePixelRatioOf(context);
        final width = (constraints.biggest.width * _dpr).toInt();
        final height = (constraints.biggest.height * _dpr).toInt();
        if (width > 0 && height > 0) {
          widget.target.resize(width, height);
        }

        return Focus(
          focusNode: _focusNode,
          onKeyEvent: _handleKeyEvent,
          child: Listener(
            onPointerDown: (event) {
              _focusNode.requestFocus();
              _handlePointerEvent(event, SlintPointerEventKind.down);
            },
            onPointerMove: (event) =>
                _handlePointerEvent(event, SlintPointerEventKind.move),
            onPointerUp: (event) =>
                _handlePointerEvent(event, SlintPointerEventKind.up),
            onPointerSignal: _handlePointerSignal,
            child: SizedBox.expand(
              child: _image != null
                  ? RawImage(image: _image, fit: BoxFit.fill)
                  : Container(color: Colors.grey[300]),
            ),
          ),
        );
      },
    );
  }

  void _handlePointerEvent(PointerEvent event, SlintPointerEventKind kind) {
    final offset = event.localPosition;
    widget.target.dispatchPointerEvent(
      SlintPointerEvent(
        kind: kind,
        x: offset.dx * _dpr,
        y: offset.dy * _dpr,
        button: SlintPointerButton.left,
        scrollDeltaX: 0,
        scrollDeltaY: 0,
      ),
    );
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final offset = event.localPosition;
      widget.target.dispatchPointerEvent(
        SlintPointerEvent(
          kind: SlintPointerEventKind.scroll,
          x: offset.dx * _dpr,
          y: offset.dy * _dpr,
          button: SlintPointerButton.left,
          scrollDeltaX: -event.scrollDelta.dx * _dpr,
          scrollDeltaY: -event.scrollDelta.dy * _dpr,
        ),
      );
    }
  }

  void _sendKey(String text) {
    widget.target.dispatchKeyEvent(SlintKeyEvent(text: text, pressed: true));
    widget.target.dispatchKeyEvent(SlintKeyEvent(text: text, pressed: false));
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (event.character != null && event.character!.isNotEmpty) {
        _sendKey(event.character!);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.backspace) {
        _sendKey('\u0008');
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        _sendKey('\n');
        return KeyEventResult.handled;
      }
      // ponytail: arrows/modifiers unmapped; Slint PUA key codes later
    }
    return KeyEventResult.ignored;
  }
}
