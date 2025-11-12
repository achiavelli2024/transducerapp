import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

enum ConnectionStatus { disconnected, connecting, connected, error }

class TcpConnection {
  Socket? _socket;
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _dataController = StreamController<Uint8List>.broadcast();
  final _errorController = StreamController<Object>.broadcast();

  Stream<ConnectionStatus> get statusStream => _statusController.stream;
  Stream<Uint8List> get dataStream => _dataController.stream;
  Stream<Object> get errorStream => _errorController.stream;

  bool get isConnected => _socket != null;
  InternetAddress? get remoteAddress => _socket?.remoteAddress;

  Future<void> connect(String host, int port,
      {Duration timeout = const Duration(seconds: 5),
        int retries = 0,
        Duration retryDelay = const Duration(seconds: 1)}) async {
    _statusController.add(ConnectionStatus.connecting);
    int attempts = 0;
    while (true) {
      attempts++;
      try {
        _socket = await Socket.connect(host, port).timeout(timeout);
        _socket!.listen((Uint8List data) {
          _dataController.add(data);
        }, onDone: () {
          _handleDisconnect();
        }, onError: (err) {
          _handleError(err);
        }, cancelOnError: true);
        _statusController.add(ConnectionStatus.connected);
        return;
      } catch (e) {
        _statusController.add(ConnectionStatus.error);
        _errorController.add(e);
        _socket = null;
        if (attempts > retries) rethrow;
        await Future.delayed(retryDelay);
      }
    }
  }

  Future<void> disconnect() async {
    // Try graceful close first, then force destroy
    try {
      await _socket?.close();
    } catch (_) {}
    try {
      // ensure it's fully closed
      _socket?.destroy();
    } catch (_) {}
    _socket = null;
    _statusController.add(ConnectionStatus.disconnected);
  }

  Future<void> send(String text) async {
    if (_socket == null) throw SocketException('Socket not connected');
    try {
      final bytes = utf8.encode(text);
      _socket!.add(bytes);
      await Future.delayed(const Duration(milliseconds: 10));
    } catch (e) {
      _errorController.add(e);
      rethrow;
    }
  }

  void _handleDisconnect() {
    try {
      _socket?.destroy();
    } catch (_) {}
    _socket = null;
    _statusController.add(ConnectionStatus.disconnected);
  }

  void _handleError(Object error) {
    _errorController.add(error);
    _handleDisconnect();
    _statusController.add(ConnectionStatus.error);
  }

  void dispose() {
    try {
      _socket?.destroy();
    } catch (_) {}
    _statusController.close();
    _dataController.close();
    _errorController.close();
  }
}