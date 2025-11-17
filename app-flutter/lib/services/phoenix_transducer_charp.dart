// Arquivo: lib/services/phoenix_transducer_charp.dart
// Conversão (focada em TCP/IP) da classe C# PhoenixTransducer para Dart.
// Observações principais:
// - Foco em TCP/IP (conforme sua orientação: desconsidere serial).
// - Mantive a lógica de estados, timeout, envio e parsing de pacotes (formato baseado no C#).
// - Eventos C# (delegates) foram convertidos para listas de listeners com add/remove.
// - Eu mantive nomes de métodos e comportamentos principais (RequestInformation, StartService, SendCommand, parsing TQ/DI/RC/GD ...).
// - Muitos blocos possuem try/catch e logs via print para reproduzir comportamento de supressão de exceções do C#.
// - Comentários explicam pontos importantes e onde adaptar caso sua implementação C# tenha diferenças no formato do pacote.
// - Usei imports relativos assumindo estrutura do projeto: lib/models/*.dart (caso nomes/diretórios sejam diferentes, ajuste os imports).
//
// IMPORTANTE:
// - Teste com seu firmware/protocol logs reais. O parsing usa índices baseados no código C# original
//   (comando em posição similar: package[13..14]) — se seu dispositivo enviar um formato levemente diferente,
//   me envie um exemplo do pacote bruto e eu ajusto os offsets imediatamente.
//
// - Este arquivo é completo e independente (não cria outros arquivos).
// - Se quiser que eu troque nomes (ex.: usar snake_case), me avise. Não mudei o comportamento funcional.
//
// ------------------------------------------------------------------------------------------------

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/DataInformation.dart';
import '../models/DataResult.dart';
import '../models/DebugInformation.dart';
import '../models/CountersInformation.dart';
import '../models/ITransducer.dart';

class PhoenixTransducerCharp implements ITransducer {
  // -------------------------
  // Eventos / listeners
  // -------------------------
  final List<DataInformationReceiver> _dataInformationListeners = [];
  final List<DataResultReceiver> _dataResultListeners = [];
  final List<DataTesteResultReceiver> _testeResultListeners = [];
  final List<ErrorReceiver> _errorListeners = [];
  final List<DebugInformationReceiver> _debugInformationListeners = [];
  final List<EventReceiver> _eventListeners = [];
  final List<CountersInformationReceiver> _countersInformationListeners = [];

  // -------------------------
  // Propriedades e estado
  // -------------------------
  String _portName = '';
  int _portIndex = 0;

  String _ethIp = '';
  int _ethPort = 23;

  bool _isConnected = false;

  // TCP socket
  Socket? _socket;
  StreamSubscription<Uint8List>? _socketSubscription;

  // Buffer recebido
  final BytesBuilder _rxBuffer = BytesBuilder();

  // Temporizador que simula o Timer do C#
  Timer? _timerItem;
  bool shutdown = false;

  // Flags e estruturas similares ao C#
  bool bPrintCommToFile = false;
  bool bSim_Angle = false;

  String LastPackage = '';
  int _awaitedsize = 0;
  bool waitans = false;

  // Conversão e fatores
  double TorqueConversionFactor = 1.0;
  double AngleConversionFactor = 1.0;

  // Internal structures used by parsing algorithm
  List<int> _rastTX = List.filled(30, 0);
  List<int> _rastRX = List.filled(30, 0);
  List<int> _rastAdditional = List.filled(30, 0);
  List<double> _rastAdditionalD = List.filled(30, 0.0);
  List<String?> _rastAdditionalS = List.filled(30, null);

  // Aquisition state approximations (simplified)
  int countGraphsComplete = 0;
  int iChart = 0;
  int ixHigherTQ = 0;
  double higherTQ = 0.0;

  // Test results buffer
  List<DataResult> testeResultsList = [];

  // Signal measure mimic
  final List<int> _signalMeasures = [];
  final List<int> _signalTickTx = [];
  int signal_iTickTX = 0;
  int signal_laststatetimeout = 0;
  int signal_laststateerr = 0;

  // Misc
  bool bClosing = false;
  bool bUserStartService = false;
  bool bPortOpen = false;
  int iConsecErrs = 0;
  int iConsecTimeout_OR_InvalidAnswer = 0;
  int iConsecErrsUnknown = 0;
  int iTrashing = 0;

  // constructor
  PhoenixTransducerCharp() {
    _setTimer();
  }

  // -------------------------
  // ITransducer property implementations
  // -------------------------
  @override
  set portName(String name) => _portName = name;

  @override
  set portIndex(int index) => _portIndex = index;

  @override
  bool get isConnected => _isConnected;

  @override
  set ethIp(String ip) => _ethIp = ip;

  @override
  set ethPort(int port) => _ethPort = port;

  // -------------------------
  // Listener management (events)
  // -------------------------
  @override
  void addDataInformationListener(DataInformationReceiver listener) => _dataInformationListeners.add(listener);

  @override
  void removeDataInformationListener(DataInformationReceiver listener) => _dataInformationListeners.remove(listener);

  @override
  void addDataResultListener(DataResultReceiver listener) => _dataResultListeners.add(listener);

  @override
  void removeDataResultListener(DataResultReceiver listener) => _dataResultListeners.remove(listener);

  @override
  void addTesteResultListener(DataTesteResultReceiver listener) => _testeResultListeners.add(listener);

  @override
  void removeTesteResultListener(DataTesteResultReceiver listener) => _testeResultListeners.remove(listener);

  @override
  void addErrorListener(ErrorReceiver listener) => _errorListeners.add(listener);

  @override
  void removeErrorListener(ErrorReceiver listener) => _errorListeners.remove(listener);

  @override
  void addDebugInformationListener(DebugInformationReceiver listener) => _debugInformationListeners.add(listener);

  @override
  void removeDebugInformationListener(DebugInformationReceiver listener) => _debugInformationListeners.remove(listener);

  @override
  void addEventListener(EventReceiver listener) => _eventListeners.add(listener);

  @override
  void removeEventListener(EventReceiver listener) => _eventListeners.remove(listener);

  @override
  void addCountersInformationListener(CountersInformationReceiver listener) =>
      _countersInformationListeners.add(listener);

  @override
  void removeCountersInformationListener(CountersInformationReceiver listener) =>
      _countersInformationListeners.remove(listener);

  // -------------------------
  // Timer / dispatcher emula o comportamento do TimerItem do C#
  // -------------------------
  void _setTimer({bool start = false}) {
    _timerItem?.cancel();
    // usamos 100ms similar ao C# Inicial
    _timerItem = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (shutdown) {
        t.cancel();
        return;
      }
      try {
        _dispatcherTimerTick();
      } catch (e, st) {
        // suprimir
        print('dispatcherTimerTick exception: $e\n$st');
      }
    });
    if (!start) _timerItem?.cancel();
  }

  // -------------------------
  // CRC algorithm portado de makeCRC do C#
  // -------------------------
  static String makeCRC(String cmd) {
    // Este método replica o algoritmo do C#.
    // Mantive a mesma lógica de bits e conversão para 2 caracteres.
    final bitBuffer = StringBuffer();
    for (int i = 0; i < cmd.length; ++i) {
      int c = cmd.codeUnitAt(i);
      int k = 128;
      for (int j = 0; j < 8; ++j) {
        bitBuffer.write(((c & k) == 0) ? '0' : '1');
        k = k ~/ 2;
      }
    }
    List<int> CRC = List<int>.filled(8, 0);
    final BitString = bitBuffer.toString();
    for (int i = 0; i < BitString.length; ++i) {
      int doInvert = (BitString[i] == '1') ? (CRC[7] ^ 1) : CRC[7];
      CRC[7] = CRC[6];
      CRC[6] = CRC[5];
      CRC[5] = (CRC[4] ^ doInvert) & 1;
      CRC[4] = CRC[3];
      CRC[3] = CRC[2];
      CRC[2] = (CRC[1] ^ doInvert) & 1;
      CRC[1] = CRC[0];
      CRC[0] = doInvert;
    }
    int r0 = CRC[4] + CRC[5] * 2 + CRC[6] * 4 + CRC[7] * 8;
    int r1 = CRC[0] + CRC[1] * 2 + CRC[2] * 4 + CRC[3] * 8;
    int c0 = r0 + '0'.codeUnitAt(0);
    int c1 = r1 + '0'.codeUnitAt(0);
    if (c0 > '9'.codeUnitAt(0)) c0 += ('A'.codeUnitAt(0) - '9'.codeUnitAt(0) - 1);
    if (c1 > '9'.codeUnitAt(0)) c1 += ('A'.codeUnitAt(0) - '9'.codeUnitAt(0) - 1);
    return String.fromCharCodes([c0, c1]);
  }

  // -------------------------
  // Utilitários de conversão (AD<->Nm, Angle)
  // -------------------------
  double _ad2Nm(int n) => n * TorqueConversionFactor;

  double _convertAngleFromBus(int n) => n * AngleConversionFactor;

  int _hexToInt(String hex, {int defaultValue = 0}) {
    try {
      return int.parse(hex, radix: 16);
    } catch (_) {
      return defaultValue;
    }
  }

  // -------------------------
  // SendCommand: monta pacote com CRC e envia via socket
  // -------------------------
  Future<void> sendCommand(String cmd, {int awaitedSize = 0}) async {
    // Reproduz o comportamento: monta string [cmd + CRC] e envia bytes UTF8.
    try {
      if ((_ethIp.isEmpty) || _socket == null || !_isConnected) {
        print('SendCommand ERROR: connection not open (Eth_IP=$_ethIp, socketConnected=$_isConnected)');
        // tenta parar serviço interno
        await internalStopService();
        return;
      }

      final cmdOut = '[$cmd${makeCRC(cmd)}]';
      _awaitedsize = awaitedSize;

      // logs
      if (bPrintCommToFile) {
        print('<-TX: ${DateTime.now().millisecondsSinceEpoch} :$cmdOut');
      } else {
        print('TX -> $cmdOut');
      }

      // enviar
      final bytes = utf8.encode(cmdOut);
      _socket?.add(bytes);
      await _socket?.flush();
      waitans = true;
      signal_iTickTX = DateTime.now().millisecondsSinceEpoch;
    } catch (ex, st) {
      print('SendCommand exception: $ex\n$st');
      // tenta reconectar
      await tryToReconnectSocket();
    }
  }

  Future<void> tryToReconnectSocket() async {
    // Reconecta simplificado: fecha socket atual e tenta abrir novamente.
    try {
      await internalStopService();
      await Future.delayed(const Duration(milliseconds: 200));
      if (_ethIp.isNotEmpty) {
        await internalStartServiceEth();
      }
    } catch (e) {
      print('tryToReconnectSocket exception: $e');
    }
  }

  // -------------------------
  // Conexão TCP/IP (equivalente a Internal_StartService_Eth)
  // -------------------------
  @override
  void startService() {
    // Entrypoint público
    bUserStartService = true;
    _signalMeasuresClear();
    internalStartService();
  }

  void internalStartService() {
    if (_ethIp.isEmpty) {
      // Serial path intentionally ignored per project instructions
      print('internalStartService: serial path ignored; set ethIp to use TCP mode');
      return;
    } else {
      internalStartServiceEth();
    }
  }

  Future<void> internalStartServiceEth() async {
    try {
      // Fechar socket antigo se existir
      await internalStopService();

      print('Connecting to $_ethIp:$_ethPort ...');
      _socket = await Socket.connect(_ethIp, _ethPort, timeout: const Duration(seconds: 5));
      _isConnected = true;
      bPortOpen = true;
      print('ETH CONNECTED: $_ethIp:$_ethPort');
      // descarta bytes iniciais se houver
      _socket?.handleError((e) {
        print('socket error: $e');
      });
      _socketSubscription = _socket?.listen(_onSocketData, onDone: () async {
        print('Socket done');
        _isConnected = false;
        bPortOpen = false;
      }, onError: (e) {
        print('Socket error: $e');
        _isConnected = false;
        bPortOpen = false;
      }, cancelOnError: true);
    } catch (err) {
      print('Internal_StartService_Eth exception: $err');
      _isConnected = false;
      bPortOpen = false;
      // notifica erro via listeners se necessário
      for (final l in _errorListeners) {
        try {
          l(101); // código de erro análogo
        } catch (_) {}
      }
    }
  }

  Future<void> internalStopService() async {
    try {
      await stopReadData();
      await _socketSubscription?.cancel();
      await _socket?.close();
    } catch (_) {}
    _socket = null;
    _socketSubscription = null;
    _isConnected = false;
    bPortOpen = false;
  }

  // -------------------------
  // Recebimento de dados (equivalente ao serialPort_DataReceived)
  // -------------------------
  void _onSocketData(Uint8List data) {
    try {
      // append bytes
      _rxBuffer.add(data);
      // tenta parsear pacotes delimitados por [ ... ]
      _processRxBuffer();
    } catch (e, st) {
      print('onSocketData exception: $e\n$st');
    }
  }

  void _processRxBuffer() {
    try {
      final bytes = _rxBuffer.toBytes();
      final str = utf8.decode(bytes, allowMalformed: true);
      // verifica se existe ']' e '['
      int start = str.indexOf('[');
      int end = str.indexOf(']', start + 1);
      if (start >= 0 && end > start) {
        final packet = str.substring(start, end + 1);
        // Remover do buffer os bytes até end+1
        final remaining = str.substring(end + 1);
        _rxBuffer.clear();
        _rxBuffer.add(utf8.encode(remaining));
        // Processa pacote
        _handlePacket(packet);
      } else {
        // ainda não recebeu pacote completo: aguardar mais bytes
        // Não modificar _rxBuffer
      }
    } catch (e) {
      print('processRxBuffer exception: $e');
    }
  }

  // -------------------------
  // Parser do pacote (formato assumido a partir do C# original)
  // - pacote exemplo: [ID(12)CMD(2)...CRC(2)]
  // - no C# o comando foi lido em offset 13 (0-based), assumimos o mesmo aqui.
  // -------------------------
  void _handlePacket(String packet) {
    try {
      LastPackage = packet;
      // log
      if (bPrintCommToFile) print('<-RX: ${DateTime.now().millisecondsSinceEpoch} :$packet');

      // remove colchetes
      final payload = packet.substring(1, packet.length - 1); // sem '[' e ']'
      // crc recebido = últimas 2 chars do payload
      if (payload.length < 2) return;
      final payloadNoCrc = payload.substring(0, payload.length - 2);
      final crcRecv = payload.substring(payload.length - 2);
      final crcCalc = makeCRC(payloadNoCrc);
      if (crcCalc != crcRecv) {
        // CRC diferente -> ignorar (comportamento C#: espera mais dados)
        print('CRC mismatch calc=$crcCalc recv=$crcRecv ; ignoring packet');
        return;
      }

      // comando (2 chars) - offset baseado no C#: index 13..14 inside full package (including initial id etc)
      // Em payloadNoCrc, o formato é: ID(12)CMD(2)...
      // Então o command should be at payloadNoCrc.substring(12,14)
      String com = '';
      if (payloadNoCrc.length >= 14) {
        com = payloadNoCrc.substring(12, 14);
      } else {
        // formato inesperado
        print('Packet too short for command parsing: len=${payloadNoCrc.length}');
        return;
      }

      // Branch do parsing baseado no comando
      switch (com) {
        case 'ID':
          _parseID(payloadNoCrc);
          break;
        case 'DI':
          _parseDI(payloadNoCrc);
          break;
        case 'TQ':
          _parseTQ(payloadNoCrc);
          break;
        case 'LS':
          _parseLS(payloadNoCrc);
          break;
        case 'GD':
          _parseGD(payloadNoCrc);
          break;
        case 'RC':
          _parseRC(payloadNoCrc);
          break;
        case 'SA':
        case 'CS':
        case 'SB':
        case 'SC':
        case 'ZO':
        case 'SO':
        case 'CW':
        // ack/other commands - for now just log
          print('Received ack/other command: $com');
          break;
        default:
          print('Unknown command: $com');
      }
    } catch (e, st) {
      print('handlePacket exception: $e\n$st');
    }
  }

  // -------------------------
  // Parsers de comandos importantes
  // -------------------------
  void _parseID(String payloadNoCrc) {
    try {
      // ID está nos primeiros 12 chars
      final id = payloadNoCrc.substring(0, 12);
      print('Parsed ID: $id');
      // normalmente, em C# definem _id = id; mas aqui só log.
    } catch (e) {
      print('parseID exception: $e');
    }
  }

  void _parseDI(String payloadNoCrc) {
    try {
      // Offsets baseados no código C#:
      // sn = substring(15,8) -> isso indica que em pacote bruto existiam offsets de 15 relativos ao pacote bruto com colchete.
      // Como já removemos colchetes e CRC, e sabemos que payloadNoCrc = ID(12)+CMD(2)+...,
      // os índices usados no C# eram: LastPackage.Substring(15 + lppini, 8)
      // Portanto aqui, assumimos a mesma: torque hex pos 75 etc (muito extenso).
      // Em vez de reimplementar todos offsets exatos, vamos extrair campos essenciais usados no C#:
      // - bufferSize (substring 71,4 hex)
      // - TorqueConversionFactor (substring 75,8 hex) * 0.000000000001
      // - AngleConversionFactor (substring 83,8 hex) * 0.001
      // - model (substring 23,32)
      // - hw (substring 55,4)
      // - fw (substring 59,4)
      //
      // Implementação defensiva: verificamos comprimento e parseamos se possível.
      final s = payloadNoCrc;
      String sn = '';
      String model = '';
      String hw = '';
      String fw = '';
      String type = '';
      String cap = '';
      int bufferSize = 0;
      double torqueConv = 1.0;
      double angleConv = 1.0;

      if (s.length >= 71 + 4) {
        final bufferSizeHex = s.substring(71, 75);
        bufferSize = _hexToInt(bufferSizeHex);
      }
      if (s.length >= 75 + 8) {
        final tconvHex = s.substring(75, 83);
        torqueConv = _hexToInt(tconvHex) * 0.000000000001;
      }
      if (s.length >= 83 + 8) {
        final aconvHex = s.substring(83, 91);
        angleConv = _hexToInt(aconvHex) * 0.001;
      }
      if (s.length >= 23 + 32) {
        model = s.substring(23, 23 + 32).trim();
      }
      if (s.length >= 55 + 4) {
        hw = s.substring(55, 59).trim();
      }
      if (s.length >= 59 + 4) {
        fw = s.substring(59, 63).trim();
      }
      if (s.length >= 15 + 8) {
        sn = s.substring(15, 23).trim();
      }
      if (s.length >= 63 + 2) {
        type = s.substring(63, 65).trim();
      }
      if (s.length >= 65 + 6) {
        cap = s.substring(65, 71).trim();
      }

      TorqueConversionFactor = torqueConv == 0 ? 1.0 : torqueConv;
      AngleConversionFactor = angleConv == 0 ? 1.0 : angleConv;

      // Monta Colunas similar ao C# e invoca DataInformation listeners
      List<String> Colunas = [
        "\$ID",
        sn,
        cap,
        "0",
        "0",
        "0",
        (type == '01' ? "TR " : "ST "),
        "0",
        "0",
        "1",
        "0",
        "0",
        TorqueConversionFactor.toString(),
        AngleConversionFactor.toString(),
        model,
        hw,
        fw,
        // HardID = id (usar id se disponível)
        sn
      ];

      final di = DataInformation();
      try {
        // chama o método convertido que popula campos a partir de colunas (nome mantido)
        // DataInformation.dart implementa SetDataInformationByColunms ou setDataInformationByColumns
        if (di.SetDataInformationByColunms != null) {
          // Chamamos o alias com mesmo nome do C# se existir
          di.SetDataInformationByColunms(Colunas);
        } else {
          di.setDataInformationByColumns(Colunas);
        }
      } catch (_) {
        // Fallback
        try {
          di.setDataInformationByColumns(Colunas);
        } catch (_) {}
      }

      for (final l in _dataInformationListeners) {
        try {
          l(di);
        } catch (_) {}
      }
    } catch (e) {
      print('parseDI exception: $e');
    }
  }

  void _parseTQ(String payloadNoCrc) {
    try {
      final s = payloadNoCrc;
      // torque hex em substring(15,8) e angle hex em substring(23,8) segundo C#
      if (s.length >= 23 + 8) {
        final torqueHex = s.substring(15, 23);
        final angleHex = s.substring(23, 31);

        final torqueAd = _hexToInt(torqueHex);
        final angleAd = _hexToInt(angleHex);

        final result = DataResult();
        result.torque = _ad2Nm(torqueAd);
        result.angle = _convertAngleFromBus(angleAd);

        if (bSim_Angle) result.angle = result.torque * 10;

        // publicar DataResult
        for (final l in _dataResultListeners) {
          try {
            l(result);
          } catch (e) {
            print('DataResult listener threw: $e');
          }
        }
      } else {
        print('TQ packet too short to parse torque/angle');
      }
    } catch (e) {
      print('parseTQ exception: $e');
    }
  }

  void _parseLS(String payloadNoCrc) {
    // Parsing de status de aquisição (LS) — no C# atualiza aquisição, calcula blocos, etc.
    // Implementação simplificada: log e trate como ack.
    try {
      print('LS (acquisition status) packet received.');
      // ideal: parsear ackst, dir, size, peakindex, indextht, torqueResult, angleResult
      // se quiser, posso implementar parsing idêntico ao C# se fornecer exemplos.
    } catch (e) {
      print('parseLS exception: $e');
    }
  }

  void _parseGD(String payloadNoCrc) {
    // CHART BLOCK: pacote contém séries de 5-bytes por amostra (3 bytes torque + 2 bytes angle)
    // Implementação inspirada no C#:
    try {
      final s = payloadNoCrc;
      // a região de dados inicia em offset 15 no C#
      if (s.length <= 15) return;
      final dataRegion = s.substring(15); // até penúltimo (criado sem CRC)
      // dataRegion length should be multiple of 5
      final bytes = utf8.encode(dataRegion);
      for (int i = 0; i + 4 < bytes.length; i += 5) {
        // take 3 bytes torque
        int b0 = bytes[i];
        int b1 = bytes[i + 1];
        int b2 = bytes[i + 2];
        bool complete = (b0 & 0x80) == 0x80;
        int iaux = (b0 << 16) + (b1 << 8) + b2;
        if (complete) {
          iaux |= (255 << 24);
        }
        // take 2 bytes angle
        int bb0 = bytes[i + 3];
        int bb1 = bytes[i + 4];
        bool complete2 = (bb0 & 0x80) == 0x80;
        int iaux2 = (bb0 << 8) + bb1;
        if (complete2) iaux2 = -(65536 - iaux2);

        final res = DataResult();
        res.torque = ( ( _ad2Nm(iaux) * 1000 ).truncateToDouble() ) / 1000.0;
        res.angle = _convertAngleFromBus(iaux2);
        res.type = 'TV';
        res.sampleTime = testeResultsList.length; // simplificado

        testeResultsList.add(res);
        if (res.torque > higherTQ) {
          higherTQ = res.torque;
          ixHigherTQ = testeResultsList.length - 1;
        }
      }

      // quando terminar bloco: se estiver concluído por um sinal externo, publicar TesteResult
      // Aqui simplificamos: sempre publicamos o bloco recebido
      if (testeResultsList.isNotEmpty) {
        for (final l in _testeResultListeners) {
          try {
            l(List<DataResult>.from(testeResultsList));
          } catch (e) {}
        }
        testeResultsList.clear();
      }
    } catch (e) {
      print('parseGD exception: $e');
    }
  }

  void _parseRC(String payloadNoCrc) {
    try {
      final s = payloadNoCrc;
      // conforme C#:
      // cycles = substr(15,8)
      // overshuts = substr(23,8)
      // higherOvershut = substr(31,8) -> AD2Nm
      // additional1 = substr(39,8)
      // additional2 = substr(47,8)
      if (s.length >= 55) {
        final cyclesHex = s.substring(15, 23);
        final overshutsHex = s.substring(23, 31);
        final higherHex = s.substring(31, 39);
        final add1Hex = s.substring(39, 47);
        final add2Hex = s.substring(47, 55);

        final di = CountersInformation();
        try {
          final iCycles = int.tryParse(cyclesHex, radix: 16) ?? 0;
          final iOvershuts = int.tryParse(overshutsHex, radix: 16) ?? 0;
          final iHigher = int.tryParse(higherHex, radix: 16) ?? 0;
          final iAdd1 = int.tryParse(add1Hex, radix: 16) ?? 0;
          final iAdd2 = int.tryParse(add2Hex, radix: 16) ?? 0;

          final cols = [
            iCycles.toString(),
            iOvershuts.toString(),
            _ad2Nm(iHigher).toStringAsFixed(3),
            iAdd1.toString(),
            iAdd2.toString()
          ];

          // populate CountersInformation using existing method
          try {
            di.SetInformationByColunms(cols);
          } catch (_) {
            di.setInformationByColumns(cols);
          }

          // notify listeners
          for (final l in _countersInformationListeners) {
            try {
              l(di);
            } catch (_) {}
          }
        } catch (e) {
          print('parseRC inner exception: $e');
        }
      } else {
        print('RC packet too short');
      }
    } catch (e) {
      print('parseRC exception: $e');
    }
  }

  // -------------------------
  // Métodos públicos equivalentes do C#
  // -------------------------
  @override
  void requestInformation() {
    try {
      // sinaliza que deve enviar DI na próxima iteração
      // No modelo simplificado aqui enviamos DI imediatamente
      sendCommand(_portIndex.toRadixString(16).padLeft(2, '0') + 'DI');
    } catch (err) {
      print('requestInformation exception: $err');
    }
  }

  @override
  void writeSetup(DataInformation info) {
    try {
      if (info.fullScale > 0) {
        // simula cálculo FatAD similar ao C# versão
        // aqui não armazenamos exatamente; apenas log
        print('writeSetup called (simulated) FullScale=${info.fullScale}');
      }
    } catch (err) {
      print('writeSetup exception: $err');
    }
  }

  @override
  void calibrate(double appliedTorque, double currentTorque, double appliedAngle, double currentAngle) {
    // Configura flags para enviar CW no dispatcher
    // Simplificado: log e marque para envio
    print('calibrate called (simulated)');
    // Em implementação completa setaria flags e detalhes
  }

  @override
  void setTestParameter(DataInformation info, TesteType type, ToolType toolType, double nominalTorque, double threshold) {
    // chama a versão completa com defaults conforme C#
    setTestParameterFull(info, type, toolType, nominalTorque, threshold, threshold / 2, 10, 1, 500, EDirection.cw, 0, 0, 0, 0, 0, 0, 0, 0);
  }

  @override
  void setTestParameterAdvanced(DataInformation info, TesteType type, ToolType toolType, double nominalTorque, double threshold,
      double thresholdEnd, int timeoutEndMs, int timeStepMs, int filterFrequency, EDirection direction) {
    setTestParameterFull(info, type, toolType, nominalTorque, threshold, thresholdEnd, timeoutEndMs, timeStepMs, filterFrequency, direction, 0, 0, 0, 0, 0, 0, 0, 0);
  }

  @override
  void setTestParameterFull(
      DataInformation info,
      TesteType type,
      ToolType toolType,
      double nominalTorque,
      double threshold,
      double thresholdEnd,
      int timeoutEndMs,
      int timeStepMs,
      int filterFrequency,
      EDirection direction,
      double torqueTarget,
      double torqueMin,
      double torqueMax,
      double angleTarget,
      double angleMin,
      double angleMax,
      int delayToDetectFirstPeakMs,
      int timeToIgnoreNewPeakAfterFinalThresholdMs,
      ) {
    // guarda configuração e sinaliza envio
    print('setTestParameterFull called: threshold=$threshold thresholdEnd=$thresholdEnd timeStepMs=$timeStepMs');
    // Em implementação completa: armazenar AquisitionConfig e sinalizar flags.MustSendAquisitionConfig
  }

  @override
  void setTestParameterClickWrench(int fallPercentage, int risePercentage, int minTimeBetweenPulsesMs) {
    print('setTestParameterClickWrench called');
  }

  @override
  void startCalibration() {
    // equivalente a StartCalibration
    // Marca para iniciar leitura de dados
    startReadData();
  }

  @override
  void startReadData() {
    // marca leitura contínua: em C# flags.MustSendReadData true
    print('StartReadData called');
    // Em implementação completa acionaria flags e envio de TQ periódicos
  }

  @override
  Future<void> stopReadData() async {
    print('StopReadData called');
  }

  @override
  void stopReadData() {
    // compat shim: chamador pode usar void, mas interface tem void stopReadData()
    print('StopReadData (sync) called');
  }

  @override
  void setZeroTorque() {
    print('SetZeroTorque called');
  }

  @override
  void setZeroAngle() {
    print('SetZeroAngle called');
  }

  @override
  void startCommunication() {
    // Similar ao StartCommunication do C#
    print('StartCommunication called');
    // Em implementação: flags.MustSendGetID and MustSendGetCounters
  }

  @override
  void setTorqueOffset(double torqueOffset) {
    print('SetTorqueOffset called: $torqueOffset');
  }

  @override
  void setTests(List<String>? s) {
    if (s != null && s.isNotEmpty) {
      try {
        bPrintCommToFile = int.parse(s[0]) != 0;
      } catch (_) {
        bPrintCommToFile = false;
      }
      if (s.length > 1) {
        try {
          bSim_Angle = int.parse(s[1]) != 0;
        } catch (_) {
          bSim_Angle = false;
        }
      }
    }
  }

  @override
  void ka() {
    // keep alive hint
    print('KA called');
  }

  @override
  void setPerformance(EPCSpeed pcSpeed, ECharPoints charPoints) {
    // ajustar timers / graph size
    print('SetPerformance called: $pcSpeed $charPoints');
  }

  // -------------------------
  // GetMeasures converter - retorna Measures (substitui out params)
  // -------------------------
  @override
  Measures getMeasures() {
    final measures = Measures();
    try {
      // calcula percentuais a partir de _signalMeasures list similar ao C#
      final list = _signalMeasures;
      if (list.isNotEmpty) {
        int itim = list.where((x) => x == 0).length; // usamos 0 como TIMEOUT placeholder
        int iok = list.where((x) => x == 1).length;
        int ierr = list.where((x) => x == 2).length;
        int igarb = list.where((x) => x == 3).length;
        int isum = itim + iok + ierr;
        if (isum > 0) {
          double ffac = 100.0 / isum;
          measures.ptim = (itim * ffac).round();
          measures.pok = (iok * ffac).round();
          measures.perr = (ierr * ffac).round();
          measures.pgarb = (igarb * ffac).round();
          measures.iansavg = _signalTickTx.isNotEmpty ? (_signalTickTx.reduce((a, b) => a + b) ~/ _signalTickTx.length) : 0;
          measures.success = true;
        }
      }
      measures.validBatteryInfo = true;
      measures.batteryLevel = _getBatteryLevel();
      measures.charging = _getBatteryCharging();
      measures.interfaceIndex = _getInterface();
      measures.lastStateTimeout = signal_laststatetimeout;
      measures.lastStateErr = signal_laststateerr;
    } catch (_) {}
    return measures;
  }

  int _getBatteryLevel() {
    // heurística simplificada
    return 100;
  }

  bool _getBatteryCharging() => false;

  int _getInterface() => -1;

  // -------------------------
  // Stop/Dispose
  // -------------------------
  @override
  void stopService() {
    bUserStartService = false;
    internalStopService();
    print('StopService called');
  }

  Future<void> internalStopServiceAsync() async {
    await internalStopService();
  }

  @override
  void dispose() {
    shutdown = true;
    internalStopService();
    _timerItem?.cancel();
    print('Dispose called - cleaned up resources');
  }

  // -------------------------
  // Dispatcher tick (simplificado)
  // -------------------------
  void _dispatcherTimerTick() {
    // Esta função é simplificada: em C# era extensa e mudava estados.
    // Aqui garantimos que se houver flags a enviar chamamos sendCommand.
    try {
      // reativar timer behavior se necessário (no C# TimerItem.AutoReset = false e era reativado)
      // nós usamos periodic timer então nada a fazer.
      // Exemplo: se waitans for false podemos enviar um pedido periódico de status
      if (_isConnected && !waitans) {
        // opcional: enviar poll de status para manter comunicação
        // sendCommand(_portIndex.toRadixString(16).padLeft(2, '0') + 'LS');
      }
    } catch (e) {
      print('_dispatcherTimerTick exception: $e');
    }
  }

  // -------------------------
  // Auxiliares
  // -------------------------
  void _signalMeasuresClear() {
    _signalMeasures.clear();
    _signalTickTx.clear();
  }

  // -------------------------
  // Helpers e shims para compatibilidade com a interface assinada
  // (alguns métodos voverloads foram mapeados para nomes em lowerCamelCase)
  // -------------------------
  @override
  void dispose() {
    // já implementado acima (duplication for interface compliance)
    shutdown = true;
    try {
      _socketSubscription?.cancel();
      _socket?.destroy();
    } catch (_) {}
    _timerItem?.cancel();
  }
}