// PhoenixTransducerClient - implementação do protocolo (TCP), CRC, parsing TQ/GD/DI/FR
// - Detecta automaticamente o _id enviado pelo transdutor (ID/DI) e passa a prefixar os comandos com ele.
// - Emite streams: onDataResult (cada TQ), onTesteResult (lista de samples GD/FR), onLog (linhas de log).
// - Não altera nada do seu C# — apenas replica a leitura por TCP no Flutter.
// - Comentários em português explicam cada parte para você aprender.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class DataResult {
  String type; // "TV" (stream sample), "FR" (final result), "TQ" (single)
  double torque;
  double angle;
  int sampleTime;
  int thresholdDir;
  int resultDir;
  DataResult({
    this.type = '',
    this.torque = 0,
    this.angle = 0,
    this.sampleTime = 0,
    this.thresholdDir = 0,
    this.resultDir = 0,
  });
}

class DataInformation {
  String hardId = '';
  String model = '';
  double torqueConversionFactor = 1.0;
  double angleConversionFactor = 1.0;
  int bufferSize = 0;
}

class PhoenixTransducerClient {
  final String host;
  final int port;
  Socket? _socket;
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  // Streams para UI e para o app usar
  final StreamController<DataResult> _dataResultController = StreamController.broadcast();
  final StreamController<List<DataResult>> _testeResultController = StreamController.broadcast();
  final StreamController<String> _logController = StreamController.broadcast();

  Stream<DataResult> get onDataResult => _dataResultController.stream;
  Stream<List<DataResult>> get onTesteResult => _testeResultController.stream;
  Stream<String> get onLog => _logController.stream;

  // Buffer de recepção (mantém bytes incompletos)
  final BytesBuilder _rxBuffer = BytesBuilder();

  // Fatores de conversão (serão atualizados ao receber DI)
  double torqueConversionFactor = 1.0;
  double angleConversionFactor = 1.0;

  // ID do transdutor (obtido do pacote ID), usado para prefixar comandos.
  String _id = '000000000000'; // default zeros até receber ID.

  // Flags
  bool waitAnswer = false;
  int awaitedSize = 0;

  PhoenixTransducerClient({ required this.host, this.port = 23 });

  // Conecta via TCP
  Future<void> connect({ Duration timeout = const Duration(seconds: 5) }) async {
    _log('Connecting to $host:$port');
    try {
      _socket = await Socket.connect(host, port, timeout: timeout);
      _isConnected = true;
      _socket!.listen(_onData, onError: _onError, onDone: _onDone, cancelOnError: true);
      _log('Connected to $host:$port');
    } catch (e) {
      _log('Connect error: $e');
      rethrow;
    }
  }

  // Desconecta
  Future<void> disconnect() async {
    _log('Disconnecting');
    try {
      await _socket?.close();
    } catch (e) {
      _log('Disconnect error: $e');
    } finally {
      _socket = null;
      _isConnected = false;
    }
  }

  // --- Envio de comandos ---
  // sendCommand recebe o payload sem o ID e automaticamente o prefixa com _id atual.
  Future<void> sendCommand(String cmdWithoutId, { int awaited = 0 }) async {
    if (!_isConnected || _socket == null) {
      _log('SendCommand: not connected');
      return;
    }

    // monta payload = id + cmdWithoutId (id tem 12 chars)
    final payloadStr = (_id.padRight(12, '0').substring(0,12)) + cmdWithoutId;
    final payloadBytes = utf8.encode(payloadStr);

    // CRC calculado sobre os bytes do payload (mapa 1:1) => retorna 2 ASCII bytes
    final crc = _makeCRCBytes(payloadBytes);

    // monta frame: '[' + payload + crc + ']'
    final framed = <int>[];
    framed.add(0x5B); // '['
    framed.addAll(payloadBytes);
    framed.addAll(crc);
    framed.add(0x5D); // ']'

    _log('TX -> ${_safePrintable(Uint8List.fromList(framed))}');

    try {
      _socket!.add(framed);
      await _socket!.flush();
      waitAnswer = true;
      awaitedSize = awaited;
    } catch (e) {
      _log('SendCommand error: $e');
    }
  }

  // Wrappers de alto nível que chamam sendCommand com o comando sem ID (o client prefixa)
  Future<void> setZeroTorque() async {
    // C# usava ZO + flags; aqui chamamos 'ZO' + payload de exemplo '10' (ajuste se necessário)
    await sendCommand('ZO10');
    _log('SetZeroTorque called (sent ZO10 prefixed by id=$_id)');
  }

  Future<void> setZeroAngle() async {
    await sendCommand('ZO01');
    _log('SetZeroAngle called (sent ZO01 prefixed by id=$_id)');
  }

  Future<void> setTestParameterClickWrench(int fallPct, int risePct, int minTimeMs) async {
    final s = _formatHex(fallPct, 2) + _formatHex(risePct, 2) + _formatHex(minTimeMs, 2);
    await sendCommand('CS$s');
    _log('SetTestParameter_ClickWrench called: $fallPct, $risePct, $minTimeMs (CS$s) prefixed by id=$_id');
  }

  Future<void> setTestParameterFull({
    required double thresholdIniNm,
    required double thresholdEndNm,
    required int timeoutEndMs,
    required int timeStepMs,
    required int filterFreq,
    required int direction, // 0 CW, 1 CCW
  }) async {
    final tIni = Nm2AD(thresholdIniNm);
    final tEnd = Nm2AD(thresholdEndNm);
    String s = '';
    s += _formatHex(tIni, 8);
    s += _formatHex(tEnd, 8);
    s += _formatHex(_limitInt(timeoutEndMs, 1, 0xFFFF), 4);
    s += _formatHex(_limitInt(timeStepMs, 1, 0xFFFF), 4);
    s += _formatHex(_limitInt(filterFreq, 500, 20000), 4);
    s += _formatHex(direction, 2);
    s += '01'; // toolType default
    await sendCommand('SA$s');
    _log('SetTestParameter (full) called (SA...) prefixed by id=$_id');
  }

  Future<void> startReadData() async {
    await sendCommand('TQ');
    _log('StartReadData called (TQ prefixed by id=$_id)');
  }

  Future<void> stopReadData() async {
    waitAnswer = false;
    _log('StopReadData called (local flag)');
  }

  // -------------------- Recepção / parsing --------------------

  void _onData(Uint8List chunk) {
    // chunk já é bytes brutos do socket
    _logHex('socket RAW', chunk);
    _rxBuffer.add(chunk);
    _tryParseBuffer();
  }

  void _onError(Object e) {
    _log('Socket error: $e');
    _isConnected = false;
  }

  void _onDone() {
    _log('Socket closed by remote');
    _isConnected = false;
  }

  void _tryParseBuffer() {
    final buffer = _rxBuffer.toBytes();
    int start = _indexOfByte(buffer, 0x5B); // '['
    if (start < 0) {
      _rxBuffer.clear();
      return;
    }
    int end = _indexOfByteFrom(buffer, 0x5D, start + 1); // ']'
    while (start >= 0 && end > start) {
      final frameLen = end - start + 1;
      final frameBytes = buffer.sublist(start, start + frameLen);
      _processFrame(frameBytes);
      final remaining = buffer.sublist(start + frameLen);
      _rxBuffer.clear();
      if (remaining.isNotEmpty) _rxBuffer.add(remaining);
      final newBuf = _rxBuffer.toBytes();
      start = _indexOfByte(newBuf, 0x5B);
      end = (start >= 0) ? _indexOfByteFrom(newBuf, 0x5D, start + 1) : -1;
    }
  }

  void _processFrame(Uint8List frameBytes) {
    _log('RX raw: ${_safePrintable(frameBytes)}');
    if (frameBytes.length < 4) {
      _log('Frame muito curto');
      return;
    }
    final payloadWithCrc = frameBytes.sublist(1, frameBytes.length - 1); // drop [ and ]
    if (payloadWithCrc.length < 3) {
      _log('Payload muito curto para CRC');
      return;
    }
    final crcRecv = payloadWithCrc.sublist(payloadWithCrc.length - 2);
    final payloadBytes = payloadWithCrc.sublist(0, payloadWithCrc.length - 2);
    final crcCalc = _makeCRCBytes(payloadBytes);

    if (!_listEquals(crcCalc, crcRecv)) {
      _log('PARSER CRC calc=${_bytesToAscii(crcCalc)} recv=${_bytesToAscii(crcRecv)} -> MISMATCH, ignorando frame');
      return;
    } else {
      _log('PARSER CRC ok: ${_bytesToAscii(crcCalc)}');
    }

    // comando em posição fixa: bytes 13..14 (0-based) dentro do payload
    if (payloadBytes.length >= 14) {
      final com = _bytesToAscii(payloadBytes.sublist(13, 15));
      _log('PARSER command=$com payloadLen=${payloadBytes.length}');

      if (com == 'ID') {
        // extrai ID: os primeiros 12 bytes do payload
        try {
          final idStr = _bytesToAscii(payloadBytes.sublist(0, 12));
          _id = idStr;
          _log('ID recebido: _id=$_id. Usarei este id para prefixar comandos.');
        } catch (e) {
          _log('Erro parse ID: $e');
        }
        return;
      }

      switch (com) {
        case 'TQ':
          _parseTQ(payloadBytes);
          break;
        case 'DI':
          _parseDI(payloadBytes);
          break;
        case 'GD':
          _parseGD(payloadBytes);
          break;
        case 'LS':
          _log('LS (status) recebido');
          break;
        case 'RC':
          _log('RC (counters) recebido');
          break;
        default:
          _log('Comando desconhecido: $com');
      }
    } else {
      _log('Payload muito curto para identificar comando');
    }
  }

  void _parseTQ(Uint8List payload) {
    // torque hex em substring(15,23) e angle em substring(23,31) (8 chars ASCII hex cada)
    try {
      if (payload.length >= 31) {
        final torqueHexBytes = payload.sublist(15, 23); // 8 bytes ASCII hex
        final angleHexBytes = payload.sublist(23, 31);
        final torqueHex = _bytesToAscii(torqueHexBytes);
        final angleHex = _bytesToAscii(angleHexBytes);
        final torqueAd = int.parse(torqueHex, radix: 16);
        final angleAd = int.parse(angleHex, radix: 16);
        final torqueNm = AD2Nm(torqueAd);
        final angleDeg = ConvertAngleFromBus(angleAd);
        final dr = DataResult(type: 'TQ', torque: torqueNm, angle: angleDeg);
        _log('PARSED TQ torqueHex=$torqueHex torqueAd=$torqueAd torqueNm=$torqueNm angleHex=$angleHex angleAd=$angleAd angleDeg=$angleDeg');
        _dataResultController.add(dr);
      } else {
        _log('TQ payload too short');
      }
    } catch (e) {
      _log('TQ parse error: $e');
    }
  }

  void _parseDI(Uint8List payload) {
    try {
      final sn = payload.length >= 23 ? _bytesToAscii(payload.sublist(15, 23)) : '';
      final model = payload.length >= 55 ? _bytesToAscii(payload.sublist(23, 55)) : '';
      if (payload.length >= 91) {
        try {
          final torqueConvHex = _bytesToAscii(payload.sublist(75, 83));
          final angleConvHex = _bytesToAscii(payload.sublist(83, 91));
          torqueConversionFactor = int.parse(torqueConvHex, radix: 16) * 0.000000000001;
          angleConversionFactor = int.parse(angleConvHex, radix: 16) * 0.001;
        } catch (_) {
          torqueConversionFactor = 1.0;
          angleConversionFactor = 1.0;
        }
      }
      _log('DI parsed - sn:$sn model:$model torqueConv:$torqueConversionFactor angleConv:$angleConversionFactor');
    } catch (e) {
      _log('DI parse error: $e');
    }
  }

  void _parseGD(Uint8List payload) {
    // Chart block: a partir do offset 15 os samples são em blocos de 5 bytes: 3 torque + 2 angle
    try {
      final samples = <DataResult>[];
      final len = payload.length;
      for (int i = 15; i + 4 < len; i += 5) {
        final b0 = payload[i];
        final b1 = payload[i + 1];
        final b2 = payload[i + 2];
        final b3 = payload[i + 3];
        final b4 = payload[i + 4];

        bool bcomplete = (b0 & 0x80) == 0x80;
        int iaux = (b0 << 16) + (b1 << 8) + b2;
        if (bcomplete) iaux |= (255 << 24);

        bool b2complete = (b3 & 0x80) == 0x80;
        int iaux2 = (b3 << 8) + b4;
        if (b2complete) iaux2 = -(65536 - iaux2);

        final torque = AD2Nm(iaux).toDouble();
        final angle = ConvertAngleFromBus(iaux2);
        final dr = DataResult(type: 'TV', torque: torque, angle: angle);
        samples.add(dr);
      }
      _log('GD parsed - samples count: ${samples.length}');
      if (samples.isNotEmpty) {
        _testeResultController.add(samples);
      }
    } catch (e) {
      _log('GD parse error: $e');
    }
  }

  // -------------------- Helpers e CRC --------------------
  List<int> _makeCRCBytes(List<int> payload) {
    final bitBuffer = StringBuffer();
    for (var c in payload) {
      int k = 128;
      for (int j = 0; j < 8; j++) {
        bitBuffer.write(((c & k) == 0) ? '0' : '1');
        k = k >> 1;
      }
    }
    final crc = List<int>.filled(8, 0);
    final bitStr = bitBuffer.toString();
    for (int i = 0; i < bitStr.length; i++) {
      int doInvert = (bitStr[i] == '1') ? (crc[7] ^ 1) : crc[7];
      crc[7] = crc[6];
      crc[6] = crc[5];
      crc[5] = crc[4] ^ doInvert;
      crc[4] = crc[3];
      crc[3] = crc[2];
      crc[2] = crc[1] ^ doInvert;
      crc[1] = crc[0];
      crc[0] = doInvert;
    }
    int res0 = crc[4] + crc[5] * 2 + crc[6] * 4 + crc[7] * 8 + '0'.codeUnitAt(0);
    int res1 = crc[0] + crc[1] * 2 + crc[2] * 4 + crc[3] * 8 + '0'.codeUnitAt(0);
    if (res0 > '9'.codeUnitAt(0)) res0 += ('A'.codeUnitAt(0) - '9'.codeUnitAt(0) - 1);
    if (res1 > '9'.codeUnitAt(0)) res1 += ('A'.codeUnitAt(0) - '9'.codeUnitAt(0) - 1);
    return [res0, res1];
  }

  // AD -> Nm
  double AD2Nm(int n) => n * torqueConversionFactor;
  double ConvertAngleFromBus(int n) => n * angleConversionFactor;
  int Nm2AD(double n) => (n / (torqueConversionFactor == 0 ? 1.0 : torqueConversionFactor)).round();

  // -------------------- utilitários de bytes/strings --------------------
  String _bytesToAscii(List<int> bytes) {
    try {
      return ascii.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  String _safePrintable(Uint8List bytes) {
    try {
      final s = latin1.decode(bytes);
      final printable = s.runes.where((r) => r >= 32 && r < 127).length;
      if (s.isEmpty) return '';
      if (printable / s.length < 0.5) {
        return _toHex(bytes);
      }
      return s;
    } catch (_) {
      return _toHex(bytes);
    }
  }

  String _toHex(List<int> bytes) {
    final sb = StringBuffer();
    for (var b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0').toUpperCase() + ' ');
    }
    return sb.toString().trim();
  }

  int _indexOfByte(Uint8List list, int byte) {
    for (int i = 0; i < list.length; i++) {
      if (list[i] == byte) return i;
    }
    return -1;
  }

  int _indexOfByteFrom(Uint8List list, int byte, int from) {
    for (int i = from; i < list.length; i++) {
      if (list[i] == byte) return i;
    }
    return -1;
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) if (a[i] != b[i]) return false;
    return true;
  }

  String _formatHex(int value, int nibbleCount) {
    return value.toRadixString(16).toUpperCase().padLeft(nibbleCount, '0');
  }

  int _limitInt(int v, int min, int max) {
    if (v < min) return min;
    if (v > max) return max;
    return v;
  }

  void _log(String s) {
    final line = '${DateTime.now().toIso8601String()} - $s';
    // ignore: avoid_print
    print(line);
    _logController.add(line);
  }

  void _logHex(String title, Uint8List buffer) {
    final sb = StringBuffer();
    sb.write('$title: ${buffer.length} bytes - ');
    for (var b in buffer) {
      sb.write(b.toRadixString(16).padLeft(2, '0').toUpperCase() + ' ');
    }
    _log(sb.toString());
  }

  void dispose() {
    _dataResultController.close();
    _testeResultController.close();
    _logController.close();
    try { _socket?.destroy(); } catch (_) {}
  }
}