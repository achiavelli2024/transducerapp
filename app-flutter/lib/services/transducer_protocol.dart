// Implementação inicial do protocolo do transdutor (framing + CRC + parser mínimo)
// Use junto com TcpConnection que você já tem.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'tcp_connection.dart';

class TransducerProtocol {
  final TcpConnection _conn;

  // Stream com payloads válidos (conteúdo entre '[' e ']', sem CRC)
  final StreamController<String> _payloadController = StreamController.broadcast();
  Stream<String> get payloadStream => _payloadController.stream;

  // stream de pacotes brutos válidos (incluindo CRC) se precisar
  final StreamController<String> _rawPacketController = StreamController.broadcast();
  Stream<String> get rawPacketStream => _rawPacketController.stream;

  // buffer para acumular bytes recebidos
  final List<int> _rxBuffer = [];

  StreamSubscription<Uint8List>? _dataSub;
  StreamSubscription<Object>? _errSub;

  TransducerProtocol(this._conn) {
    _dataSub = _conn.dataStream.listen(_onData, onError: (e) => _onError(e));
    _errSub = _conn.errorStream.listen((e) => _onError(e));
  }

  void _onError(Object e) {
    // repassa ou loga se necessário
  }

  void _onData(Uint8List bytes) {
    _rxBuffer.addAll(bytes);
    _processBuffer();
  }

  void _processBuffer() {
    // procura por pacotes [ ... ]
    while (true) {
      final start = _rxBuffer.indexOf('['.codeUnitAt(0));
      if (start < 0) {
        // sem '[' no buffer, descartar dados antes se necessário
        // mantemos buffer limpo para evitar crescimento indefinido
        _rxBuffer.clear();
        return;
      }
      final end = _rxBuffer.indexOf(']'.codeUnitAt(0), start + 1);
      if (end < 0) {
        // ainda não chegou o ']', esperar mais dados
        if (start > 0) {
          // descarta lixo antes do '['
          _rxBuffer.removeRange(0, start);
        }
        return;
      }

      // temos um pacote completo
      final packetBytes = _rxBuffer.sublist(start + 1, end); // conteúdo entre [ e ]
      // remover do buffer
      _rxBuffer.removeRange(0, end + 1);

      // tentar interpretar como texto ASCII/UTF8
      String content;
      try {
        content = utf8.decode(packetBytes);
      } catch (e) {
        // fallback hex (sem separador)
        content = packetBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      }

      // valida CRC: últimos 2 caracteres representam CRC (conforme C#).
      if (content.length < 2) {
        continue; // pacote inválido
      }
      final payload = content.substring(0, content.length - 2);
      final crcReceived = content.substring(content.length - 2).toUpperCase();
      final crcCalc = makeCRC(payload);
      if (crcCalc == crcReceived) {
        _rawPacketController.add('[$content]');
        _payloadController.add(payload); // payload sem CRC
      } else {
        // CRC inválido -> ignorar ou logar
        // print('CRC inválido. calc:$crcCalc recv:$crcReceived payload:$payload');
      }
    }
  }

  // monta comando (ex.: id + "DI") -> adiciona CRC e envia: [cmdCRC]
  Future<void> sendCommand(String cmd) async {
    final crc = makeCRC(cmd);
    final full = '[$cmd$crc]';
    await _conn.send(full);
  }

  // exemplo de função de alto nível
  Future<void> requestInformation(String id) async {
    // comando DI no C#: _id + "DI"
    await sendCommand('$id' + 'DI');
  }

  // implementa o makeCRC conforme o algoritmo do C# (porta)
  static String makeCRC(String cmd) {
    // construir bitstring como String
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

    // CRC armazenado como bits em array de ints (0/1)
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

  void dispose() {
    _dataSub?.cancel();
    _errSub?.cancel();
    _payloadController.close();
    _rawPacketController.close();
  }
}