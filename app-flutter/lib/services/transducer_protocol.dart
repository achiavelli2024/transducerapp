// Substitua este arquivo: lib/services/transducer_protocol.dart
// Adições principais:
// - heartbeat / keepalive (auto polling TQ)
// - startAutoReadLoop / stopAutoReadLoop
// - proteção de sendCommand quando socket desconectado
// - reconexão: não implementa reconnect automático no socket (TcpConnection faz isso), mas evita envios quando desconectado.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'tcp_connection.dart';
import '../models/transducer_models.dart';

class ProtocolTimeoutException implements Exception {
  final String message;
  ProtocolTimeoutException(this.message);
  @override
  String toString() => 'ProtocolTimeoutException: $message';
}

class TransducerProtocol {
  final TcpConnection _conn;

  final StreamController<String> _rawPacketController = StreamController.broadcast();
  final StreamController<String> _payloadController = StreamController.broadcast();
  final StreamController<DataResult> _dataResultController = StreamController.broadcast();
  final StreamController<DataInformation> _infoController = StreamController.broadcast();

  Stream<DataResult> get dataResultStream => _dataResultController.stream;
  Stream<DataInformation> get infoStream => _infoController.stream;
  Stream<String> get rawPacketStream => _rawPacketController.stream;
  Stream<String> get payloadStream => _payloadController.stream;

  final List<int> _rxBuffer = [];
  StreamSubscription<Uint8List>? _tcpDataSub;
  StreamSubscription<Object>? _tcpErrSub;

  Completer<String>? _pendingCompleter;
  String? _pendingExpectedCom;
  Timer? _pendingTimer;

  double torqueConversionFactor = 1.0;
  double angleConversionFactor = 1.0;

  bool waitAns = false;
  int awaitedSize = 0;

  String _id = '000000000000';

  // heartbeat / auto read loop
  Timer? _autoReadTimer;
  Duration autoReadInterval = const Duration(milliseconds: 800);
  bool _autoReading = false;

  TransducerProtocol(this._conn) {
    _tcpDataSub = _conn.dataStream.listen(_onTcpData, onError: _onTcpError, onDone: () {
      // socket closed: clean pending to avoid deadlocks
      _completePendingWithError(SocketException('Socket closed (onDone)'));
    });
    _tcpErrSub = _conn.errorStream.listen(_onTcpError);
  }

  void _onTcpError(Object err) {
    _completePendingWithError(err);
  }

  // Start an automatic periodic TQ polling loop (keeps device producing readings)
  void startAutoReadLoop({Duration? interval}) {
    if (_autoReading) return;
    if (interval != null) autoReadInterval = interval;
    _autoReadTimer = Timer.periodic(autoReadInterval, (_) async {
      if (!_conn.isConnected) return;
      try {
        // use current id if known, else default
        final cmd = (_id.isNotEmpty ? _id : '000000000000') + 'TQ';
        // don't await forever; read with expectedCom 'TQ' and short timeout
        await sendCommand(cmd, expectedCom: 'TQ', timeoutMs: 1200);
        // result arrives via dataResultStream
      } catch (_) {
        // ignore individual timeouts — keep polling
      }
    });
    _autoReading = true;
  }

  void stopAutoReadLoop() {
    _autoReadTimer?.cancel();
    _autoReadTimer = null;
    _autoReading = false;
  }

  Future<String?> sendCommand(String cmd, {String? expectedCom, int timeoutMs = 1200, int awaitedSizeParam = 0}) async {
    if (!_conn.isConnected) {
      throw SocketException('Socket not connected (cannot send command)');
    }

    if (_pendingCompleter != null) {
      throw StateError('Another pending command in progress');
    }

    awaitedSize = awaitedSizeParam;
    final crc = makeCRC(cmd);
    final full = '[$cmd$crc]';
    waitAns = true;

    if (expectedCom != null) {
      _pendingCompleter = Completer<String>();
      _pendingExpectedCom = expectedCom.toUpperCase();
      _pendingTimer = Timer(Duration(milliseconds: timeoutMs), () {
        if (!_pendingCompleter!.isCompleted) {
          _pendingCompleter!.completeError(ProtocolTimeoutException('Timeout waiting for $expectedCom'));
        }
        _clearPending();
      });
    }

    try {
      await _conn.send(full);
    } catch (e) {
      _completePendingWithError(e);
      rethrow;
    }

    if (_pendingCompleter != null) {
      try {
        final resp = await _pendingCompleter!.future;
        return resp;
      } finally {
        _clearPending();
        waitAns = false;
      }
    } else {
      waitAns = false;
      return null;
    }
  }

  Future<String?> requestInformation([String? id]) async {
    if (!_conn.isConnected) {
      throw SocketException('Socket not connected (cannot request DI)');
    }
    if (id != null) {
      final cmd = id + 'DI';
      return await sendCommand(cmd, expectedCom: 'DI', timeoutMs: 1500);
    } else {
      return null;
    }
  }

  void _completePendingWithError(Object err) {
    try {
      if (_pendingCompleter != null && !_pendingCompleter!.isCompleted) {
        _pendingCompleter!.completeError(err);
      }
    } catch (_) {}
    _clearPending();
  }

  void _clearPending() {
    _pendingTimer?.cancel();
    _pendingTimer = null;
    _pendingCompleter = null;
    _pendingExpectedCom = null;
    awaitedSize = 0;
    waitAns = false;
  }

  void _onTcpData(Uint8List bytes) {
    _rxBuffer.addAll(bytes);
    _processBuffer();
  }

  void _processBuffer() {
    while (true) {
      final start = _rxBuffer.indexOf('['.codeUnitAt(0));
      if (start < 0) {
        if (_rxBuffer.length > 4096) _rxBuffer.clear();
        return;
      }
      if (start > 0) _rxBuffer.removeRange(0, start);

      int end = _rxBuffer.indexOf(']'.codeUnitAt(0), 1);
      if (end < 0) {
        if (awaitedSize > 0 && _rxBuffer.length >= awaitedSize) {
          end = awaitedSize - 1;
        } else {
          return;
        }
      }

      final contentBytes = _rxBuffer.sublist(1, end);
      _rxBuffer.removeRange(0, end + 1);

      String content;
      try {
        content = utf8.decode(contentBytes);
      } catch (e) {
        content = contentBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      }

      content = content.replaceAll(RegExp(r'[\x00\r\n]'), '');
      if (content.length < 2) continue;

      final payload = content.substring(0, content.length - 2);
      final crcReceived = content.substring(content.length - 2).toUpperCase();
      final crcCalc = makeCRC(payload);

      if (crcCalc != crcReceived) {
        _rawPacketController.add('[${content}] (invalid CRC calc:$crcCalc recv:$crcReceived)');
        continue;
      }

      _rawPacketController.add('[$content]');
      _payloadController.add(payload);

      _handlePayload(payload);
    }
  }

  void _handlePayload(String payload) {
    try {
      if (payload.length >= 14) {
        final com = payload.substring(12, 14).toUpperCase();

        // complete pending if matching
        if (_pendingCompleter != null && _pendingExpectedCom != null) {
          if (payload.contains(_pendingExpectedCom!)) {
            if (!_pendingCompleter!.isCompleted) _pendingCompleter!.complete(payload);
          }
        }

        if (com == 'ID' || payload.contains('ID')) {
          if (payload.length >= 12) _id = payload.substring(0, 12);
          return;
        }

        if (com == 'DI' || payload.contains('DI')) {
          if (payload.length >= 90) {
            final id = payload.substring(0, 12);
            final sn = payload.substring(14, 14 + 8).trim();
            final model = payload.substring(22, 22 + 32).trim();
            final hw = payload.substring(54, 54 + 4).trim();
            final fw = payload.substring(58, 58 + 4).trim();
            final type = payload.substring(62, 62 + 2).trim();
            final cap = payload.substring(64, 64 + 6).trim();
            final bufferSizeHex = payload.substring(70, 70 + 4);
            final bufferSize = int.tryParse(bufferSizeHex, radix: 16) ?? 0;
            final torqueConvHex = payload.substring(74, 74 + 8);
            final angleConvHex = payload.substring(82, 82 + 8);
            final torqueConvRaw = int.tryParse(torqueConvHex, radix: 16) ?? 0;
            final angleConvRaw = int.tryParse(angleConvHex, radix: 16) ?? 0;
            final torqueConv = torqueConvRaw * 1e-12;
            final angleConv = angleConvRaw * 0.001;
            torqueConversionFactor = torqueConv == 0 ? 1.0 : torqueConv;
            angleConversionFactor = angleConv == 0 ? 1.0 : angleConv;
            final info = DataInformation(
              id: id,
              serialNumber: sn,
              model: model,
              hw: hw,
              fw: fw,
              type: type,
              capacity: cap,
              bufferSize: bufferSize,
              torqueConversionFactor: torqueConversionFactor,
              angleConversionFactor: angleConversionFactor,
            );
            _infoController.add(info);
          }
          return;
        }

        if (com == 'TQ' || payload.contains('TQ')) {
          final allGroups = RegExp(r'([0-9A-Fa-f]{8})').allMatches(payload).toList();
          if (allGroups.length >= 2) {
            final torqueHex = allGroups[0].group(0)!;
            final angleHex = allGroups[1].group(0)!;
            final torqueAd = int.tryParse(torqueHex, radix: 16);
            final angleBus = int.tryParse(angleHex, radix: 16) ?? 0;
            if (torqueAd != null) {
              final torque = torqueAd * torqueConversionFactor;
              final angle = angleBus * angleConversionFactor;
              final id = payload.length >= 12 ? payload.substring(0, 12) : '000000000000';
              final result = DataResult(id: id, torque: torque, angle: angle, type: 'TQ');
              _dataResultController.add(result);
            }
          }
          return;
        }
      } else {
        // small payloads: maybe pending expected com — try to complete
        if (_pendingCompleter != null && _pendingExpectedCom != null && payload.contains(_pendingExpectedCom!)) {
          if (!_pendingCompleter!.isCompleted) _pendingCompleter!.complete(payload);
        }
      }
    } catch (e) {
      // ignore parse errors
    }
  }

  static String makeCRC(String cmd) {
    final StringBuffer sb = StringBuffer();
    for (var codeUnit in cmd.runes) {
      int k = 128;
      int c = codeUnit;
      for (int j = 0; j < 8; j++) {
        sb.write(((c & k) == 0) ? '0' : '1');
        k >>= 1;
      }
    }
    final String bitString = sb.toString();
    final List<int> crc = List<int>.filled(8, 0);
    for (int i = 0; i < bitString.length; i++) {
      final int bit = (bitString.codeUnitAt(i) == '1'.codeUnitAt(0)) ? 1 : 0;
      final int doInvert = (bit == 1) ? (crc[7] ^ 1) : crc[7];
      crc[7] = crc[6];
      crc[6] = crc[5];
      crc[5] = (crc[4] ^ doInvert);
      crc[4] = crc[3];
      crc[3] = crc[2];
      crc[2] = (crc[1] ^ doInvert);
      crc[1] = crc[0];
      crc[0] = doInvert;
    }
    final int val0 = crc[4] + crc[5] * 2 + crc[6] * 4 + crc[7] * 8;
    final int val1 = crc[0] + crc[1] * 2 + crc[2] * 4 + crc[3] * 8;
    String nibbleToHex(int v) {
      if (v <= 9) return String.fromCharCode('0'.codeUnitAt(0) + v);
      return String.fromCharCode('A'.codeUnitAt(0) + (v - 10));
    }
    return '${nibbleToHex(val0)}${nibbleToHex(val1)}';
  }


  // Clear internal parser state (call on disconnect)
  void reset() {
    _rxBuffer.clear();
    _clearPending();
    torqueConversionFactor = 1.0;
    angleConversionFactor = 1.0;
    _id = '000000000000';
    stopAutoReadLoop();
  }





  // Dispose and unsubscribe from connection streams (call on final dispose)
  void dispose() {
    _tcpDataSub?.cancel();
    _tcpErrSub?.cancel();
    _rawPacketController.close();
    _payloadController.close();
    _dataResultController.close();
    _infoController.close();
    _clearPending();
    stopAutoReadLoop();
  }
}