import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:jhentai/src/network/backend_api_client.dart';

const kWebWheelScrollSpeedKey = 'web_wheel_scroll_speed';

double webWheelScrollSpeedFromStorage(String? value) {
  final parsed = double.tryParse(value ?? '');
  if (parsed == null || parsed <= 0) {
    return 5.0;
  }
  return parsed.clamp(0.5, 12.0);
}

class WebWheelSpeedController extends StatelessWidget {
  const WebWheelSpeedController({
    super.key,
    required this.controller,
    required this.speed,
    required this.child,
  });

  final ScrollController? controller;
  final double speed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent) {
          return;
        }
        final c = controller;
        if (c == null || !c.hasClients) {
          return;
        }
        final delta = event.scrollDelta.dy * speed.clamp(0.5, 12.0);
        if (delta == 0) {
          return;
        }
        final position = c.position;
        final target = (position.pixels + delta)
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble();
        if ((target - position.pixels).abs() < 0.5) {
          return;
        }
        GestureBinding.instance.pointerSignalResolver.register(event, (_) {
          position.animateTo(
            target,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
          );
        });
        GestureBinding.instance.pointerSignalResolver.resolve(event);
      },
      child: child,
    );
  }
}

Future<double> loadWebWheelScrollSpeed() async {
  try {
    final value = await backendApiClient.getSetting(kWebWheelScrollSpeedKey);
    return webWheelScrollSpeedFromStorage(value);
  } catch (_) {
    return 5.0;
  }
}
