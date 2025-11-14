// app-flutter/lib/services/tcp_connection.dart
// Versão modificada: adiciona debugStream para emitir eventos detalhados (connect/disconnect/send/receive/errors).
// Não altera a API existente (statusStream, dataStream, errorStream, send, connect, disconnect).
// Comentários inclusos para te ajudar a entender cada parte.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

enum ConnectionStatus { disconnected, connecting, connected, error }

class TcpConnection {
  Socket? _socket;

  // Streams públicos já existentes
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _dataController = StreamController<Uint8List>.broadcast();
  final _errorController = StreamController<Object>.broadcast();

  // Novo: stream para mensagens de debug legíveis (útil para UI e diagnóstico)
  final _debugController = StreamController<String>.broadcast();

  Stream<ConnectionStatus> get statusStream => _statusController.stream;
  Stream<Uint8List> get dataStream => _dataController.stream;
  Stream<Object> get errorStream => _errorController.stream;

  // Novo: expõe debug stream (mensagens textuais, por exemplo "TX: [0000TQ...]")
  Stream<String> get debugStream => _debugController.stream;

  bool get isConnected => _socket != null;
  InternetAddress? get remoteAddress => _socket?.remoteAddress;

  // Conecta ao host/porta com timeout e tentativas
  Future<void> connect(String host, int port,
      {Duration timeout = const Duration(seconds: 5),
        int retries = 0,
        Duration retryDelay = const Duration(seconds: 1)}) async {
    _statusController.add(ConnectionStatus.connecting);
    _debugController.add('connect: trying $host:$port');
    int attempts = 0;
    while (true) {
      attempts++;
      try {
        // Tenta conectar
        _socket = await Socket.connect(host, port).timeout(timeout);

        // Inscreve nos eventos do socket
        _socket!.listen((Uint8List data) {
          // repassa bytes para o serviço/protocol
          _dataController.add(data);
          _debugController.add('RX raw ${data.length} bytes from ${_socket?.remoteAddress}:${_socket?.remotePort}');
        }, onDone: () {
          // Quando o socket fecha ao receber done
          _debugController.add('socket onDone (remote: ${_socket?.remoteAddress}:${_socket?.remotePort})');
          _handleDisconnect();
        }, onError: (err) {
          _debugController.add('socket onError: $err');
          _handleError(err);
        }, cancelOnError: true);

        _statusController.add(ConnectionStatus.connected);
        _debugController.add('connect: established to ${_socket!.remoteAddress.address}:${_socket!.remotePort}');
        return;
      } catch (e) {
        _statusController.add(ConnectionStatus.error);
        _errorController.add(e);
        _debugController.add('connect attempt $attempts failed: $e');
        _socket = null;
        if (attempts > retries) {
          _debugController.add('connect: no more retries, rethrowing');
          rethrow;
        }
        _debugController.add('connect: retrying in ${retryDelay.inMilliseconds}ms');
        await Future.delayed(retryDelay);
      }
    }
  }

  // Desconecta de forma graciosa e força destruição
  Future<void> disconnect() async {
    _debugController.add('disconnect: requested');
    try {
      await _socket?.close();
      _debugController.add('disconnect: socket close called');
    } catch (e) {
      _debugController.add('disconnect: close error: $e');
    }
    try {
      _socket?.destroy();
      _debugController.add('disconnect: socket destroyed');
    } catch (e) {
      _debugController.add('disconnect: destroy error: $e');
    }
    _socket = null;
    _statusController.add(ConnectionStatus.disconnected);
    _debugController.add('disconnect: complete, status DISCONNECTED emitted');
  }

  // Envia texto (com codificação UTF-8) — mantém comportamento anterior, mas agora loga o TX no debugStream
  Future<void> send(String text) async {
    if (_socket == null) {
      _debugController.add('send: fail, socket is null');
      throw SocketException('Socket not connected');
    }
    try {
      final bytes = utf8.encode(text);
      _socket!.add(bytes);
      // await small delay to let data be pushed (como antes)
      await Future.delayed(const Duration(milliseconds: 10));
      _debugController.add('TX ${bytes.length} bytes -> ${utf8.decode(bytes, allowMalformed: true)}');
    } catch (e) {
      _errorController.add(e);
      _debugController.add('send: error -> $e');
      rethrow;
    }
  }

  // Internal handlers
  void _handleDisconnect() {
    try {
      _socket?.destroy();
    } catch (_) {}
    _socket = null;
    _statusController.add(ConnectionStatus.disconnected);
    _debugController.add('handleDisconnect: socket destroyed and status DISCONNECTED emitted');
  }

  void _handleError(Object error) {
    _errorController.add(error);
    _debugController.add('handleError: $error');
    _handleDisconnect();
    _statusController.add(ConnectionStatus.error);
    _debugController.add('handleError: status ERROR emitted');
  }

  // Fecha controllers
  void dispose() {
    try {
      _socket?.destroy();
    } catch (_) {}
    _statusController.close();
    _dataController.close();
    _errorController.close();
    _debugController.close();
  }
}