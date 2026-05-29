import 'dart:async';
import 'dart:convert';

typedef EventListener = void Function(String event, dynamic data);

class EventBus {
  final _controller = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get stream => _controller.stream;

  void fire(String event, dynamic data) {
    _controller.add({'event': event, 'data': data});
  }

  String serializeEvent(Map<String, dynamic> event) {
    return jsonEncode(event);
  }

  void dispose() {
    _controller.close();
  }
}
