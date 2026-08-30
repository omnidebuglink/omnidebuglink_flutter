import 'package:flutter/material.dart';

/// RouteObserver that records the current page stack (plus a bounded event
/// history) for the get_state task. Attach it yourself:
/// `MaterialApp(navigatorObservers: [OmniDebugLink.routeObserver])`.
/// Without it get_state reports routes:null with guidance.
class OmniDebugLinkRouteTracker extends RouteObserver<PageRoute<dynamic>> {
  final List<String> _stack = [];
  final List<Map<String, dynamic>> _history = [];
  static const _maxHistory = 50;

  void _hist(String event, Route<dynamic> route) {
    _history.add({
      'ts': DateTime.now().millisecondsSinceEpoch,
      'event': event,
      'route': route.settings.name ?? route.runtimeType.toString(),
    });
    if (_history.length > _maxHistory) _history.removeAt(0);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (route is PageRoute) {
      _stack.add(route.settings.name ?? route.runtimeType.toString());
      _hist('push', route);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (route is PageRoute) {
      _stack.removeLast();
      _hist('pop', route);
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute is PageRoute) {
      if (_stack.isNotEmpty) _stack.removeLast();
      _stack.add(newRoute.settings.name ?? newRoute.runtimeType.toString());
      if (oldRoute != null) _hist('replace', oldRoute);
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    if (route is PageRoute) {
      _stack.remove(route.settings.name ?? route.runtimeType.toString());
      _hist('remove', route);
    }
  }

  List<String> get stack => List.unmodifiable(_stack);
  List<Map<String, dynamic>> get history => List.unmodifiable(_history);
  bool get attached => _stack.isNotEmpty || _history.isNotEmpty;
}
