// lib/pages/connect_page.dart
// Ajustado para comportamento igual ao C#:
// - NÃO iniciar leitura automaticamente ao conectar/receber DI
// - Botões explicitos "Iniciar Leitura" / "Parar Leitura"
// - startAcquisition envia ZO/CS/SA e só então liga o polling (_proto.startAutoReadLoop())
// - stopAcquisition pára o polling (_proto.stopAutoReadLoop())

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../services/tcp_connection.dart';
import '../services/transducer_protocol.dart';
import '../services/port_scanner.dart';
import '../services/android_network_bind.dart';
import '../models/transducer_models.dart';

class ConnectPage extends StatefulWidget {
  const ConnectPage({Key? key}) : super(key: key);

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final _ipController = TextEditingController(text: '192.168.4.1');
  final _portController = TextEditingController(text: '23');

  final TcpConnection _conn = TcpConnection();
  late TransducerProtocol _proto;

  ConnectionStatus _status = ConnectionStatus.disconnected;
  final List<String> _log = [];

  // internal buffer for throttled logging
  final List<String> _logBuffer = [];
  Timer? _logFlushTimer;

  StreamSubscription<ConnectionStatus>? _statusSub;
  StreamSubscription<Uint8List>? _dataSub;
  StreamSubscription<Object>? _errSub;
  StreamSubscription<DataResult>? _resSub;
  StreamSubscription<DataInformation>? _infoSub;
  StreamSubscription<String>? _rawPacketSub;
  StreamSubscription<String>? _payloadSub;

  DataResult? _lastResult;
  DataInformation? _deviceInfo;

  bool _scanning = false;
  bool _isReading = false; // novo: indica se a aquisição está ativa

  @override
  void initState() {
    super.initState();
    _proto = TransducerProtocol(_conn);

    // start periodic log flush (throttle UI updates)
    _logFlushTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (_logBuffer.isNotEmpty) {
        setState(() {
          _log.addAll(_logBuffer);
          if (_log.length > 400) _log.removeRange(0, _log.length - 400);
          _logBuffer.clear();
        });
      }
    });

    _statusSub = _conn.statusStream.listen((s) {
      _enqueueLog('STATUS: $s');
      setState(() => _status = s);
    });

    _dataSub = _conn.dataStream.listen((bytes) {
      final text = _tryDecode(bytes);
      _enqueueLog('RAW TCP RX (bytes): $text');
    });

    _errSub = _conn.errorStream.listen((err) {
      _enqueueLog('ERR: $err');
    });

    _resSub = _proto.dataResultStream.listen((res) {
      _enqueueLog('DATARESULT: ${res.toString()}');
      setState(() => _lastResult = res);
    });

    _infoSub = _proto.infoStream.listen((info) {
      _enqueueLog('INFO (typed): ${info.toString()}');
      setState(() => _deviceInfo = info);
      // NOT automatic start: do NOT call _proto.startAutoReadLoop() here.
      // The user action "Iniciar Leitura" will call startAcquisition().
    });

    _rawPacketSub = _proto.rawPacketStream.listen((s) {
      _enqueueLog('RAW PACKET: $s');
    });
    _payloadSub = _proto.payloadStream.listen((s) {
      _enqueueLog('PAYLOAD: $s');
    });
  }

  void _enqueueLog(String s) {
    final now = DateTime.now().toIso8601String().substring(11, 19);
    _logBuffer.add('[$now] $s');
    if (_logBuffer.length > 500) _logBuffer.removeAt(0);
  }

  String _tryDecode(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (e) {
      return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    }
  }

  Future<void> _toggleConnection() async {
    if (_conn.isConnected) {
      // ao desconectar, pare leitura e unbind
      if (_isReading) await stopAcquisition();
      try {
        await AndroidNetworkBind.unbind();
      } catch (_) {}
      await _conn.disconnect();
      _enqueueLog('Desconectado manualmente');
      return;
    }

    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 23;
    _enqueueLog('Tentando conectar em $ip:$port');

    // bind network to ensure socket routes correctly
    try {
      final bindRes = await AndroidNetworkBind.bindToWifi();
      _enqueueLog('Network bind result: $bindRes');
    } catch (e) {
      _enqueueLog('Network bind failed (continuing): $e');
    }

    try {
      await _conn.connect(ip, port, timeout: const Duration(seconds: 8), retries: 1, retryDelay: const Duration(seconds: 2));
      _enqueueLog('Conectado em $ip:$port');

      if (!_conn.isConnected) {
        _enqueueLog('Socket dropped before handshake');
        return;
      }

      try {
        _enqueueLog('Handshake: solicitando ID (000000000000ID)');
        final idPayload = await _proto.sendCommand('000000000000ID', expectedCom: 'ID', timeoutMs: 2000);
        _enqueueLog('ID payload raw: $idPayload');
        String parsedId = '000000000000';
        if (idPayload != null && idPayload.length >= 12) parsedId = idPayload.substring(0, 12);
        _enqueueLog('ID detectado: $parsedId');

        try {
          _enqueueLog('Enviando DI com id $parsedId');
          final diPayload = await _proto.requestInformation(parsedId);
          _enqueueLog('DI payload raw: $diPayload');
        } catch (e) {
          _enqueueLog('Erro DI (após ID): $e');
        }
      } catch (e) {
        _enqueueLog('Handshake ID falhou: $e');
      }
    } catch (e, st) {
      _enqueueLog('Connect failed: $e');
      _enqueueLog('Stack: $st');
    }
  }

  Future<void> _requestInfoImmediate() async {
    if (!_conn.isConnected) {
      _enqueueLog('Não conectado');
      return;
    }
    final id = '000000000000';
    try {
      _enqueueLog('Enviando DI (imediato) -> $id');
      final payload = await _proto.requestInformation(id);
      _enqueueLog('DI resposta payload: $payload');
    } catch (e) {
      _enqueueLog('Erro DI: $e');
    }
  }

  // ---------- New: Start / Stop acquisition controlled by user ----------
  // Called when user presses "Iniciar Leitura"
  Future<void> startAcquisition() async {
    if (!_conn.isConnected) {
      _enqueueLog('Não conectado - não inicia aquisição');
      return;
    }
    if (_isReading) {
      _enqueueLog('Aquisição já ativa');
      return;
    }

    _enqueueLog('Iniciando aquisição (envia parâmetros SA/CS/ZO...)');
    // chama initReadSequence (envia ZO/CS/SA) e depois liga o loop automático se bem-sucedido
    try {
      await _initReadSequence();
      // se quiser que o device "push" por si próprio, não ligue o polling; caso contrário ligue:
      _proto.startAutoReadLoop(interval: const Duration(milliseconds: 800)); // polling periódico
      setState(() => _isReading = true);
      _enqueueLog('Aquisição iniciada (auto-read ligado)');
    } catch (e) {
      _enqueueLog('Falha ao iniciar aquisição: $e');
    }
  }

  // Called when user presses "Parar Leitura"
  Future<void> stopAcquisition() async {
    if (!_isReading) {
      _enqueueLog('Aquisição não está ativa');
      return;
    }
    _enqueueLog('Parando aquisição (parando polling)');
    try {
      _proto.stopAutoReadLoop();
      // opcional: enviar comando de parada ao transdutor caso exista (ex.: ID + "SO" ou "RC" dependendo do firmware).
      // await _proto.sendCommand((_deviceInfo?.id ?? '000000000000') + 'SO', expectedCom: 'SO', timeoutMs: 600);
    } catch (e) {
      _enqueueLog('Erro ao parar aquisição: $e');
    } finally {
      setState(() => _isReading = false);
      _enqueueLog('Aquisição parada');
    }
  }

  Future<void> _readTQ() async {
    if (!_conn.isConnected) {
      _enqueueLog('Não conectado - não envia TQ');
      return;
    }
    try {
      final payload = await _proto.sendCommand((_deviceInfo?.id ?? '000000000000') + 'TQ', expectedCom: 'TQ', timeoutMs: 1500);
      _enqueueLog('TQ one-shot payload: $payload');
    } catch (e) {
      _enqueueLog('Erro TQ: $e');
    }
  }

  // initReadSequence sends ZO/CS/SA and does the minimal waits (same as before)
  Future<void> _initReadSequence({double thresholdNm = 4.0, double thresholdEndNm = 2.0}) async {
    final id = (_deviceInfo?.id ?? '000000000000');
    _enqueueLog('InitRead: usando id $id');

    try {
      await _proto.sendCommand('$id' + 'ZO10', expectedCom: 'ZO', timeoutMs: 600);
    } catch (e) {
      _enqueueLog('ZO torque erro (ok se ignorado): $e');
    }
    await Future.delayed(const Duration(milliseconds: 50));

    try {
      await _proto.sendCommand('$id' + 'ZO01', expectedCom: 'ZO', timeoutMs: 600);
    } catch (e) {
      _enqueueLog('ZO angle erro (ok se ignorado): $e');
    }
    await Future.delayed(const Duration(milliseconds: 50));

    String hexByte(int v) => v.clamp(0, 255).toRadixString(16).padLeft(2, '0').toUpperCase();
    final csPayload = hexByte(30) + hexByte(30) + hexByte(20);
    try {
      await _proto.sendCommand('$id' + 'CS' + csPayload, expectedCom: 'CS', timeoutMs: 600);
    } catch (e) {
      _enqueueLog('CS erro (ok se ignorado): $e');
    }
    await Future.delayed(const Duration(milliseconds: 50));

    final tConv = _proto.torqueConversionFactor;
    final thrAd = (thresholdNm / (tConv == 0 ? 1.0 : tConv)).round();
    final thrEndAd = (thresholdEndNm / (tConv == 0 ? 1.0 : tConv)).round();

    String hex32(int v) => v.toRadixString(16).padLeft(8, '0').toUpperCase();
    String hex16(int v) => v.toRadixString(16).padLeft(4, '0').toUpperCase();
    String hex8(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();

    final saPayload = hex32(thrAd) + hex32(thrEndAd) + hex16(1000) + hex16(1) + hex16(500) + hex8(0) + hex8(1);
    try {
      await _proto.sendCommand('$id' + 'SA' + saPayload, expectedCom: 'SA', timeoutMs: 1000);
    } catch (e) {
      _enqueueLog('SA erro (ok se ignorado): $e');
    }
    await Future.delayed(const Duration(milliseconds: 120));
  }

  Future<void> _scanPorts() async {
    final host = _ipController.text.trim();
    final portsToTry = [23, 2323, 80, 8080, 502, 5000, 9000, 5555];
    setState(() {
      _scanning = true;
    });
    _enqueueLog('Scan: iniciando varredura em $host ...');
    try {
      final open = await scanPorts(host, portsToTry, timeout: const Duration(seconds: 2));
      if (open.isEmpty) {
        _enqueueLog('Scan: nenhuma porta aberta encontrada entre: ${portsToTry.join(", ")}');
      } else {
        _enqueueLog('Scan: portas abertas: ${open.join(", ")}');
        _portController.text = open.first.toString();
      }
    } catch (e) {
      _enqueueLog('Scan error: $e');
    } finally {
      setState(() {
        _scanning = false;
      });
    }
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _dataSub?.cancel();
    _errSub?.cancel();
    _resSub?.cancel();
    _infoSub?.cancel();
    _rawPacketSub?.cancel();
    _payloadSub?.cancel();
    _proto.dispose();
    _conn.dispose();
    _logFlushTimer?.cancel();
    AndroidNetworkBind.unbind().catchError((_) {});
    super.dispose();
  }

  Widget _buildTopControls(double width) {
    return Column(children: [
      Row(children: [
        Expanded(
          flex: 2,
          child: TextField(
            controller: _ipController,
            decoration: const InputDecoration(labelText: 'IP do transdutor'),
            keyboardType: TextInputType.numberWithOptions(decimal: true),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 96,
          child: TextField(
            controller: _portController,
            decoration: const InputDecoration(labelText: 'Porta'),
            keyboardType: TextInputType.number,
          ),
        ),
      ]),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          ElevatedButton(
            onPressed: _toggleConnection,
            child: Text(_conn.isConnected ? 'Desconectar' : 'Conectar'),
          ),
          ElevatedButton(
            onPressed: _conn.isConnected ? _requestInfoImmediate : null,
            child: const Text('Request Info'),
          ),
          ElevatedButton(
            onPressed: _conn.isConnected && !_isReading ? startAcquisition : null,
            child: const Text('Iniciar Leitura'),
          ),
          ElevatedButton(
            onPressed: _conn.isConnected && _isReading ? stopAcquisition : null,
            child: const Text('Parar Leitura'),
          ),
          ElevatedButton(
            onPressed: _scanning ? null : _scanPorts,
            child: _scanning ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Scan Ports'),
          ),
        ],
      ),
    ]);
  }

  Widget _buildResultCard() {
    final torque = _lastResult?.torque != null ? _lastResult!.torque.toStringAsFixed(3) : '--';
    final angle = _lastResult?.angle != null ? _lastResult!.angle.toStringAsFixed(3) : '--';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Última leitura', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('Torque: $torque Nm', style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 4),
              Text('Ângulo: $angle º', style: const TextStyle(fontSize: 14)),
            ]),
          ),
          ElevatedButton(onPressed: _readTQ, child: const Text('Ler TQ')),
        ]),
      ),
    );
  }

  Widget _buildInfoCard() {
    if (_deviceInfo == null) return const SizedBox.shrink();
    final info = _deviceInfo!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Device Information', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('ID: ${info.id}'),
          Text('SN: ${info.serialNumber}'),
          Text('Model: ${info.model}'),
          Text('HW: ${info.hw}  FW: ${info.fw}'),
          Text('Type: ${info.type}  Capacity: ${info.capacity}'),
          Text('BufferSize: ${info.bufferSize}'),
        ]),
      ),
    );
  }

  Widget _buildLog() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6)),
      child: ListView.builder(
        itemCount: _log.length,
        reverse: true,
        itemBuilder: (context, idx) {
          final item = _log[_log.length - 1 - idx];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(item, style: const TextStyle(fontSize: 12)),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transducer - Conexão TCP'),
        actions: [
          Padding(padding: const EdgeInsets.all(8.0), child: _statusChip()),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(10.0),
          child: Column(children: [
            _buildTopControls(w),
            const SizedBox(height: 8),
            _buildResultCard(),
            const SizedBox(height: 8),
            _buildInfoCard(),
            const SizedBox(height: 8),
            Expanded(child: _buildLog()),
          ]),
        ),
      ),
    );
  }

  Widget _statusChip() {
    Color c;
    String txt;
    switch (_status) {
      case ConnectionStatus.connecting:
        c = Colors.orange;
        txt = 'Conectando';
        break;
      case ConnectionStatus.connected:
        c = Colors.green;
        txt = 'Conectado';
        break;
      case ConnectionStatus.error:
        c = Colors.red;
        txt = 'Erro';
        break;
      case ConnectionStatus.disconnected:
      default:
        c = Colors.grey;
        txt = 'Desconectado';
    }
    return Chip(label: Text(txt), backgroundColor: c.withOpacity(0.15));
  }
}