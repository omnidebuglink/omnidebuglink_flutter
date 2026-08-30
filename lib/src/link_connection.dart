import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';


/// WebSocket link to the OmniDebugLink relay.
///
/// Owns the whole connection lifecycle: hello after open, app-level heartbeat
/// (55s) so the relay DO can hibernate, a 180s inbound watchdog, exponential
/// backoff reconnect (1s -> 30s) and the permanent stop on close code 4000
/// (this token was replaced by a newer connection; one token pair = one device
/// seat, reconnecting would ping-pong with the server's kicker).
class OmniDebugLinkConnection {
  OmniDebugLinkConnection({
    required this.url,
    required Map<String, dynamic> Function() buildHello,
    required void Function(String requestId, String type,
        Map<String, dynamic> payload) onTask,
    required this.onState,
  })  : _buildHello = buildHello,
        _onTask = onTask;

  final String url;
  final Map<String, dynamic> Function() _buildHello;
  final void Function(String requestId, String type, Map<String, dynamic> payload)
      _onTask;
  final void Function(bool connected) onState;

  static const heartbeatMs = 55000;
  static const watchdogMs = 180000;
  static const backoffCapMs = 30000;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _heartbeat;
  bool _stopped = false;
  bool _connected = false;
  int _backoffMs = 1000;
  final _clock = Stopwatch()..start();
  int _lastInboundMs = 0;
  bool _replaced = false; // saw close 4000: never reconnect

  bool get isConnected => _connected;

  Future<void> start() async {
    _stopped = false;
    _runLoop();
  }

  Future<void> close() async {
    _stopped = true;
    _cancelHeartbeat();
    await _sub?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _setConnected(false);
  }

  /// Send a fresh capability hello (reconnect loop also sends one on open).
  void sendHello() => _send(jsonEncode(_buildHello()));

  void _runLoop() async {
    while (!_stopped && !_replaced) {
      try {
        final channel = WebSocketChannel.connect(Uri.parse(url));
        await channel.ready;
        if (_stopped) {
          await channel.sink.close();
          return;
        }
        _channel = channel;
        _backoffMs = 1000;
        _lastInboundMs = _monoMs();
        _setConnected(true);
        _send(jsonEncode(_buildHello()));
        _startHeartbeat();
        // Await stream completion; returns on done/error/close-4000.
        await _pump(channel);
      } catch (e) {
        _log('connection error: $e');
      } finally {
        _cancelHeartbeat();
        _setConnected(false);
      }
      if (_stopped || _replaced) break;
      await Future<void>.delayed(Duration(milliseconds: _backoffMs));
      _backoffMs =
          _backoffMs * 2 > backoffCapMs ? backoffCapMs : _backoffMs * 2;
    }
    _log('connection loop finished (stopped=$_stopped replaced=$_replaced)');
  }

  Future<void> _pump(WebSocketChannel channel) async {
    final completer = Completer<void>();
    _sub = channel.stream.listen(
      (data) {
        _lastInboundMs = _monoMs();
        if (data is String) _handleFrame(data);
      },
      onError: (Object e) {
        _log('stream error: $e');
        if (!completer.isCompleted) completer.complete();
      },
      onDone: () {
        // closeCode is only populated after the done event fires — read it
        // here, never earlier, or a 4000 would be misclassified as a normal
        // drop and we would ping-pong with the replacement connection.
        final code = channel.closeCode;
        if (code == 4000) {
          _replaced = true;
          _log('TOKEN REPLACED: another connection took over this token '
              '(close 4000). One token pair belongs to ONE device; stopping '
              'reconnects. Mint a separate token pair per device.');
        } else {
          _log('connection closed (code=$code)');
        }
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );
    return completer.future;
  }

  void _startHeartbeat() {
    _cancelHeartbeat();
    _heartbeat = Timer.periodic(const Duration(milliseconds: heartbeatMs), (_) {
      if (_monoMs() - _lastInboundMs > watchdogMs) {
        _log('watchdog: server silent >${watchdogMs}ms, dropping connection');
        _channel?.sink.close(); // triggers onDone -> reconnect
        return;
      }
      _send('{"v":1,"type":"ping"}');
    });
  }

  void _cancelHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  void _handleFrame(String text) {
    dynamic msg;
    try {
      msg = jsonDecode(text);
    } catch (_) {
      return; // non-JSON: ignore, mirroring the server
    }
    if (msg is! Map<String, dynamic>) return;
    if (msg['v'] != 1) return;
    final type = msg['type'];
    if (type == 'pong') return; // traffic already stamped by the caller
    if (type == 'task') {
      final requestId = msg['requestId'];
      final task = msg['task'];
      if (requestId is! String || task is! Map<String, dynamic>) return;
      final taskType = task['type'];
      if (taskType is! String || taskType.isEmpty) return;
      final rawPayload = task['payload'];
      final payload =
          rawPayload is Map<String, dynamic> ? rawPayload : <String, dynamic>{};
      _onTask(requestId, taskType, payload);
    }
  }

  /// Result frame builders are the ONLY frame constructors for results:
  /// every success frame must carry "ok":true (relay.ts treats a missing ok
  /// as failure — the Android client's v0.1.0 bug).
  void sendResultOk(String requestId, Object? result) {
    _send(jsonEncode(<String, dynamic>{
      'v': 1,
      'type': 'result',
      'requestId': requestId,
      'ok': true,
      'result': result,
    }));
  }

  void sendResultError(String requestId, String code, String message) {
    _send(jsonEncode(<String, dynamic>{
      'v': 1,
      'type': 'result',
      'requestId': requestId,
      'ok': false,
      'error': {'code': code, 'message': message},
    }));
  }

  void _send(String json) {
    final ch = _channel;
    if (ch == null) return;
    try {
      ch.sink.add(json);
    } catch (e) {
      _log('send failed: $e');
    }
  }

  void _setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    onState(value);
  }

  int _monoMs() => _clock.elapsedMilliseconds;

  void Function(String) onLog = (_) {};

  void _log(String message) => onLog('[omnidebuglink] $message');
}
