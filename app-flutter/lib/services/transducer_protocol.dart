// Substitua este arquivo: lib/services/transducer_protocol.dart
// Versão com correção: adiciona métodos públicos startReadData() e stopReadData()
// (erros no VSCode por falta desses métodos). Mantive todos os logs e a lógica
// de parsing/CRC/DI/TQ que já estava implementada.
//
// Passos (para você, leiga):
// 1) Abra seu projeto no VSCode.
// 2) Substitua o arquivo app-flutter/lib/services/transducer_protocol.dart por este conteúdo.
// 3) Salve e rode um hot-restart do app (ou pare e rode de novo).
// 4) Teste: conectar -> Request Info -> Iniciar Leitura -> verifique logs/valores.
//
// Comentários inline ajudam a entender cada parte.

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

  // Streams públicos
  final StreamController<String> _rawPacketController = StreamController.broadcast();
  final StreamController<String> _payloadController = StreamController.broadcast();
  final StreamController<DataResult> _dataResultController = StreamController.broadcast();
  final StreamController<DataInformation> _infoController = StreamController.broadcast();

  Stream<DataResult> get dataResultStream => _dataResultController.stream;
  Stream<DataInformation> get infoStream => _infoController.stream;
  Stream<String> get rawPacketStream => _rawPacketController.stream; // debug / logs
  Stream<String> get payloadStream => _payloadController.stream;

  // Buffer de recebimento (bytes)
  final List<int> _rxBuffer = [];
  StreamSubscription<Uint8List>? _tcpDataSub;
  StreamSubscription<Object>? _tcpErrSub;

  // Pending (quando enviamos e aguardamos resposta)
  Completer<String>? _pendingCompleter;
  String? _pendingExpectedCom;
  Timer? _pendingTimer;

  // Conversões extraídas do DI
  double torqueConversionFactor = 1.0;
  double angleConversionFactor = 1.0;

  // Flags similares ao C#
  bool waitAns = false;
  int awaitedSize = 0;

  String _id = '000000000000';

  // Auto read / polling
  Timer? _autoReadTimer;
  Duration autoReadInterval = const Duration(milliseconds: 800);
  bool _autoReading = false;

  TransducerProtocol(this._conn) {
    // Assina streams do TcpConnection
    _tcpDataSub = _conn.dataStream.listen(_onTcpData, onError: _onTcpError, onDone: () {
      _completePendingWithError(SocketException('Socket closed (onDone)'));
    });
    _tcpErrSub = _conn.errorStream.listen(_onTcpError);
  }

  void _onTcpError(Object err) {
    _completePendingWithError(err);
  }

  // ------------------ Auto read loop (interno) ------------------
  void startAutoReadLoop({Duration? interval}) {
    if (_autoReading) return;
    if (interval != null) autoReadInterval = interval;
    _autoReadTimer = Timer.periodic(autoReadInterval, (_) async {
      if (!_conn.isConnected) return;
      try {
        final cmd = (_id.isNotEmpty ? _id : '000000000000') + 'TQ';
        await sendCommand(cmd, expectedCom: 'TQ', timeoutMs: 1200);
      } catch (_) {
        // ignora timeouts individuais — polling continua
      }
    });
    _autoReading = true;
  }

  void stopAutoReadLoop() {
    _autoReadTimer?.cancel();
    _autoReadTimer = null;
    _autoReading = false;
  }

  // ------------------ MÉTODOS PÚBLICOS que a UI chama ------------------
  // Adicionamos explicitamente estes wrappers porque a ConnectPage usa esses nomes.
  // Eles mantêm semântica simples: startReadData arma polling (ou outro comportamento futuro).
  Future<void> startReadData() async {
    // Se no futuro for necessário enviar um comando "arm" ao dispositivo, adicione aqui.
    startAutoReadLoop();
  }

  Future<void> stopReadData() async {
    // Para leitura: para o polling e limpa pendências para evitar stuck futures.
    stopAutoReadLoop();
    _clearPending();
  }

  // ------------------ Envio de comando (baixo nível) ------------------
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
      // Em caso de erro no envio, completa pending com erro (se houver) e rethrow
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

  // Request information (DI) convenience
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

  // ------------------ Recepção de bytes ------------------
  void _onTcpData(Uint8List bytes) {
    _rxBuffer.addAll(bytes);
    _processBuffer();
  }

  // ------------------ Parser robusto por bytes ------------------
  void _processBuffer() {
    while (true) {
      final int start = _rxBuffer.indexOf(0x5B); // '['
      if (start < 0) {
        if (_rxBuffer.length > 4096) _rxBuffer.clear();
        return;
      }
      if (start > 0) _rxBuffer.removeRange(0, start);

      int end = -1;
      if (_rxBuffer.length > 1) end = _rxBuffer.indexOf(0x5D, 1); // ']'

      if (end < 0) {
        if (awaitedSize > 0 && _rxBuffer.length >= awaitedSize) {
          end = awaitedSize - 1;
        } else {
          return;
        }
      }

      if (end - 1 < 0) {
        _rxBuffer.removeRange(0, end + 1);
        continue;
      }

      final Uint8List contentBytes = Uint8List.fromList(_rxBuffer.sublist(1, end));
      _rxBuffer.removeRange(0, end + 1);

      if (contentBytes.length < 2) continue;

      final int payloadLen = contentBytes.length - 2;
      final Uint8List payloadBytes = Uint8List.fromList(contentBytes.sublist(0, payloadLen));
      final String crcReceived = String.fromCharCodes([contentBytes[payloadLen], contentBytes[payloadLen + 1]]).toUpperCase();

      final String crcCalc = makeCRCFromBytes(payloadBytes);

      if (crcCalc != crcReceived) {
        final String contentHex = contentBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        try {
          _rawPacketController.add('[${contentHex}] (invalid CRC calc:$crcCalc recv:$crcReceived)');
        } catch (_) {}
        continue;
      }

      // CRC OK: payloadString preserva bytes usando latin1
      final String payloadString = latin1.decode(payloadBytes);
      final String displayPayload = payloadString.replaceAll('\x00', '');

      // LOG: pacote recebido e CRC válido
      try {
        _rawPacketController.add('[RX OK] $displayPayload (crc:$crcReceived)');
        _payloadController.add(payloadString);
      } catch (_) {}

      // Processa semanticamente o payload
      _handlePayload(payloadString);
    }
  }

  // ------------------ Processamento semântico do payload ------------------
  void _handlePayload(String payload) {
    try {
      if (payload.length >= 14) {
        final com = payload.substring(12, 14).toUpperCase();

        // Se há pendingCompleter, complete quando contém expectedCom
        if (_pendingCompleter != null && _pendingExpectedCom != null) {
          if (payload.contains(_pendingExpectedCom!)) {
            if (!_pendingCompleter!.isCompleted) _pendingCompleter!.complete(payload);
          }
        }

        // ID
        if (com == 'ID' || payload.contains('ID')) {
          if (payload.length >= 12) {
            _id = payload.substring(0, 12);
            _rawPacketController.add('[PARSED ID] id=$_id');
          }
          return;
        }

        // DATA INFORMATION (DI)
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

            // LOG com detalhes para debug (útil para você ver se as conversões estão corretas)
            _rawPacketController.add('[PARSED DI] id:$id sn:$sn model:$model hw:$hw fw:$fw type:$type cap:$cap bufferSize:$bufferSize torqueConvRaw:$torqueConvRaw torqueConv:$torqueConversionFactor angleConvRaw:$angleConvRaw angleConv:$angleConversionFactor');
          }
          return;
        }

        // READ RESULT (TQ)
        if (com == 'TQ' || payload.contains('TQ')) {
          // Regexp: procura grupos de 8 hex (torque e angle)
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

              // LOG extra detalhado para debug: mostra hex, AD bruto e convertido
              _rawPacketController.add('[PARSED TQ] id:$id torqueHex:$torqueHex torqueAd:$torqueAd torqueNm:${torque.toStringAsFixed(6)} angleHex:$angleHex angleBus:$angleBus angleDeg:${angle.toStringAsFixed(6)}');

            } else {
              _rawPacketController.add('[PARSED TQ] torque hex parse fail: $torqueHex');
            }
          } else {
            _rawPacketController.add('[PARSED TQ] unexpected payload format: $payload');
          }
          return;
        }
      } else {
        // payload pequeno: talvez completar pending expected com
        if (_pendingCompleter != null && _pendingExpectedCom != null && payload.contains(_pendingExpectedCom!)) {
          if (!_pendingCompleter!.isCompleted) _pendingCompleter!.complete(payload);
        }
      }
    } catch (e) {
      _rawPacketController.add('[PARSE ERROR] $e payload:$payload');
      // não propaga exceções para não quebrar o parser
    }
  }

  // -------------- CRC helpers --------------
  static String makeCRCFromBytes(Uint8List bytes) {
    final StringBuffer sbBits = StringBuffer();
    for (final b in bytes) {
      int k = 128;
      int c = b;
      for (int j = 0; j < 8; j++) {
        sbBits.write(((c & k) == 0) ? '0' : '1');
        k >>= 1;
      }
    }
    final String bitString = sbBits.toString();
    final List<int> crc = List<int>.filled(8, 0);
    for (int i = 0; i < bitString.length; i++) {
      final int bit = (bitString.codeUnitAt(i) == '1'.codeUnitAt(0)) ? 1 : 0;
      final int doInvert = (bit == 1) ? (crc[7] ^ 1) : crc[7];
      crc[7] = crc[6];
      crc[6] = crc[5];
      crc[5] = (crc[4] ^ doInvert) & 0x1;
      crc[4] = crc[3];
      crc[3] = crc[2];
      crc[2] = (crc[1] ^ doInvert) & 0x1;
      crc[1] = crc[0];
      crc[0] = doInvert & 0x1;
    }
    final int val0 = crc[4] + crc[5] * 2 + crc[6] * 4 + crc[7] * 8;
    final int val1 = crc[0] + crc[1] * 2 + crc[2] * 4 + crc[3] * 8;
    String nibbleToHex(int v) {
      if (v <= 9) return String.fromCharCode('0'.codeUnitAt(0) + v);
      return String.fromCharCode('A'.codeUnitAt(0) + (v - 10));
    }
    return '${nibbleToHex(val0)}${nibbleToHex(val1)}';
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

  // Dispose
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