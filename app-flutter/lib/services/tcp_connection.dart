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

  Future<void> connect(String host, int port, {Duration timeout = const Duration(seconds: 5)}) async {
    _statusController.add(ConnectionStatus.connecting);
    try {
      _socket = await Socket.connect(host, port, timeout: timeout);
      _statusController.add(ConnectionStatus.connected);

      _socket!.listen((Uint8List data) {
        _dataController.add(data);
      }, onDone: () async {
        await disconnect();
      }, onError: (error) async {
        _errorController.add(error);
        await disconnect();
      }, cancelOnError: true);
    } catch (e) {
      _statusController.add(ConnectionStatus.error);
      _errorController.add(e);
      rethrow;
    }
  }

  Future<void> send(String text) async {
    if (_socket == null) throw StateError('Socket not connected');
    _socket!.add(utf8.encode(text));
    await _socket!.flush();
  }

  Future<void> disconnect() async {
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
    _statusController.add(ConnectionStatus.disconnected);
  }

  void dispose() {
    _statusController.close();
    _dataController.close();
    _errorController.close();
    try {
      _socket?.destroy();
    } catch (_) {}
  }
}