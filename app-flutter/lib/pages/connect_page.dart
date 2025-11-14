// lib/pages/connect_page.dart
// Integração com PhoenixTransducer (opção A) - interface espelho do C#
// - Usa a implementação Dart de PhoenixTransducer (TCP only)
// - Botões: Conectar / Desconectar, Request Info, Iniciar Leitura, Parar Leitura, Zeros
// - Exibe Device Information e Última leitura (TQ/Angle) e contadores simples
// - Comentários e instruções passo-a-passo para desenvolvedor/usuário leigo
//
// Alterações nesta versão:
// - Importa lib/models/data_information.dart (classe DataInformation real)
// - Atualiza todas as referências a campos de DataInformation para os nomes em camelCase
// - Mantém comportamento e callbacks já existentes

import 'dart:async';
import 'package:flutter/material.dart';

import '../models/data_information.dart'; // <- import da sua classe DataInformation (nova)
import '../services/phoenix_transducer.dart';
import '../services/transducer_logger.dart'; // logger defensivo que gravará TX/RX/erros

enum ConnectionStatus { disconnected, connecting, connected, error }

class ConnectPage extends StatefulWidget {
  const ConnectPage({Key? key}) : super(key: key);

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final TextEditingController _ipController = TextEditingController(text: '192.168.4.1');
  final TextEditingController _portController = TextEditingController(text: '23');

  PhoenixTransducer? _transducer;
  ConnectionStatus _status = ConnectionStatus.disconnected;

  // UI state mirrored from transducer callbacks
  DataInformation? _deviceInfo;
  DataResult? _lastResult;
  List<DataResult> _lastTestResults = [];
  CountersInformation? _countersInfo;
  String _message = ''; // small status/messages area

  @override
  void initState() {
    super.initState();
    // Inicializa o logger (assumindo implementação TransducerLogger)
    TransducerLogger.configure().then((_) {
      setState(() {
        _message = 'Logger inicializado';
      });
    }).catchError((e) {
      setState(() {
        _message = 'Falha ao inicializar logger: $e';
      });
    });
  }

  @override
  void dispose() {
    _disconnect();
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  // Toggle connection (Connect / Disconnect)
  Future<void> _toggleConnection() async {
    if (_status == ConnectionStatus.connected || _status == ConnectionStatus.connecting) {
      await _disconnect();
    } else {
      await _connect();
    }
  }

  // Connect: create PhoenixTransducer, assign callbacks and start service
  Future<void> _connect() async {
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 23;

    setState(() {
      _status = ConnectionStatus.connecting;
      _message = 'Conectando...';
    });

    // Create instance
    _transducer = PhoenixTransducer();

    // Assign callbacks (these will update the UI via setState)
    _transducer!.onEvent = (String ev) {
      setState(() {
        _message = 'Evento: $ev';
      });
    };

    _transducer!.onError = (int code) {
      setState(() {
        _status = ConnectionStatus.error;
        _message = 'Erro do transdutor: $code';
      });
    };

    _transducer!.onDataInformation = (DataInformation di) {
      setState(() {
        _deviceInfo = di;
        _message = 'Device information received';
      });
    };

    _transducer!.onDataResult = (DataResult dr) {
      setState(() {
        _lastResult = dr;
      });
    };

    _transducer!.onTesteResult = (List<DataResult> results) {
      setState(() {
        _lastTestResults = results;
        _message = 'TesteResult recebido: ${results.length} amostras';
      });
    };

    _transducer!.onDebugInformation = (DebugInformation dbg) {
      setState(() {
        _message = 'Debug info state=${dbg.State}';
      });
    };

    _transducer!.onCountersInformation = (CountersInformation ci) {
      setState(() {
        _countersInfo = ci;
        _message = 'Counters received';
      });
    };

    // Try to start service (connect TCP)
    try {
      await _transducer!.startService(ip, port);
      setState(() {
        _status = ConnectionStatus.connected;
        _message = 'Conectado (tentativa concluída)';
      });

      // Start communication (ask for ID and counters) similar ao C#
      _transducer!.startCommunication();
    } catch (ex) {
      setState(() {
        _status = ConnectionStatus.error;
        _message = 'Falha ao conectar: $ex';
      });
    }
  }

  // Disconnect: stop read and service and clear state
  Future<void> _disconnect() async {
    try {
      if (_transducer != null) {
        try {
          _transducer!.stopReadData();
        } catch (_) {}
        try {
          await _transducer!.stopService();
        } catch (_) {}
        try {
          await _transducer!.dispose();
        } catch (_) {}
      }
    } finally {
      setState(() {
        _transducer = null;
        _status = ConnectionStatus.disconnected;
        _deviceInfo = null;
        _lastResult = null;
        _lastTestResults = [];
        _countersInfo = null;
        _message = 'Desconectado';
      });
    }
  }

  // Request Information (DI) immediately
  void _requestInfoImmediate() {
    if (_transducer != null) {
      _transducer!.requestInformation();
      setState(() {
        _message = 'Solicitado DI (Request Info)';
      });
    }
  }

  // Init read sequence (mirror InitReadSequence in C#)
  // - Send Zero Torque (ZO), Zero Angle (ZO), CS (click wrench), SA (acquisition config), then start TQ
  Future<void> _initReadSequence() async {
    if (_transducer == null) return;
    setState(() {
      _message = 'Iniciando sequência de leitura (ZO, CS, SA, TQ)...';
    });

    // 1) Zero torque and angle (send flags; dispatcher will perform TX)
    try {
      _transducer!.setZeroTorque();
      await Future.delayed(const Duration(milliseconds: 50)); // pequeno delay conforme C# (10ms) mas maior para segurança
      _transducer!.setZeroAngle();
    } catch (e) {
      setState(() {
        _message = 'Erro ao setar zero: $e';
      });
      return;
    }

    // 2) Click-wrench params
    try {
      _transducer!.setTestParameterClickWrench(10, 20, 10); // fall=10%, rise=20%, minMs=10
      await Future.delayed(const Duration(milliseconds: 20));
    } catch (e) {
      // non-fatal
    }

    // 3) Acquisition config (SA) + SB/SC (use the new C#-compatible signature)
    //
    // IMPORTANT: phoenix_transducer.dart agora espera chamada no formato:
    //   setTestParameter(DataInformation? info, TesteType type, ToolType toolType, double nominalTorque, double threshold, { ... })
    //
    // Exemplo: aqui usamos null para DataInformation (não precisamos passar), TesteType.TorqueOnly,
    // nominalTorque = 4.0 (exemplo), threshold = 1.0 e demais parâmetros via named args.
    try {
      _transducer!.setTestParameter(
        null, // DataInformation? (opcional na nossa implementação)
        TesteType.TorqueOnly, // TesteType igual ao C#
        ToolType.ToolType1, // ToolType
        4.0, // nominalTorque (Nm) - ajuste conforme sua configuração
        1.0, // threshold (Nm)
        thresholdEnd: 0.5,
        timeoutEndMs: 100,
        timeStepMs: 10,
        filterFrequency: 500,
        direction: eDirection.CW,
        // SB params (additional) - para evitar ER do transdutor, não deixar todos zero
        torqueTarget: 4.0,
        torqueMin: 2.0,
        torqueMax: 6.0,
        angleTarget: 10.0,
        angleMin: 5.0,
        angleMax: 15.0,
        delayToDetectFirstPeakMs: 10,
        timeToIgnoreNewPeakAfterFinalThresholdMs: 10,
      );
      await Future.delayed(const Duration(milliseconds: 20));
    } catch (e) {
      // non-fatal
    }

    // 4) Start reading (TQ polling and acquisition). Dispatcher will send SA/CS/SB/SC in order
    try {
      _transducer!.startReadData();
      setState(() {
        _message = 'Leitura iniciada (TQ)';
      });
    } catch (e) {
      setState(() {
        _message = 'Erro ao iniciar leitura: $e';
      });
    }
  }

  // Stop acquisition
  void _stopReadSequence() {
    if (_transducer == null) return;
    _transducer!.stopReadData();
    setState(() {
      _message = 'Leitura parada';
    });
  }

  // Send Zeros individually (buttons)
  void _sendZeroTorque() {
    if (_transducer == null) return;
    _transducer!.setZeroTorque();
    setState(() {
      _message = 'Zero Torque enviado';
    });
  }

  void _sendZeroAngle() {
    if (_transducer == null) return;
    _transducer!.setZeroAngle();
    setState(() {
      _message = 'Zero Angle enviado';
    });
  }

  // Simple UI builder methods
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
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
            _buildTopControls(width),
            const SizedBox(height: 8),
            _buildResultCard(),
            const SizedBox(height: 8),
            _buildInfoCard(),
            const SizedBox(height: 8),
            _buildCountersCard(),
            const SizedBox(height: 8),
            Expanded(child: _buildMessageArea()),
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
        break;
    }
    return Chip(
      backgroundColor: c,
      label: Text(txt, style: const TextStyle(color: Colors.white)),
    );
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
            child: Text((_status == ConnectionStatus.connected || _status == ConnectionStatus.connecting) ? 'Desconectar' : 'Conectar'),
          ),
          ElevatedButton(
            onPressed: (_status == ConnectionStatus.connected) ? _requestInfoImmediate : null,
            child: const Text('Request Info'),
          ),
          ElevatedButton(
            onPressed: (_status == ConnectionStatus.connected) ? _initReadSequence : null,
            child: const Text('Iniciar Leitura'),
          ),
          ElevatedButton(
            onPressed: (_status == ConnectionStatus.connected) ? _stopReadSequence : null,
            child: const Text('Parar Leitura'),
          ),
          ElevatedButton(
            onPressed: (_status == ConnectionStatus.connected) ? _sendZeroTorque : null,
            child: const Text('Zero Torque'),
          ),
          ElevatedButton(
            onPressed: (_status == ConnectionStatus.connected) ? _sendZeroAngle : null,
            child: const Text('Zero Angle'),
          ),
        ],
      ),
    ]);
  }

  Widget _buildResultCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Última Leitura', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Torque: ${_lastResult != null ? _lastResult!.Torque.toStringAsFixed(3) + " Nm" : "-"}'),
              Text('Angulo: ${_lastResult != null ? _lastResult!.Angle.toStringAsFixed(3) + " °" : "-"}'),
              const SizedBox(height: 8),
              Text('Amostras de último teste: ${_lastTestResults.length}'),
            ]),
          ),
          Column(children: [
            ElevatedButton(
              onPressed: _lastResult != null ? () {} : null,
              child: const Text('Ver Valor'),
            )
          ])
        ]),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Device Information', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('ID: ${_deviceInfo != null ? _deviceInfo!.hardID : '-'}'),
          Text('KeyName: ${_deviceInfo != null ? _deviceInfo!.keyName : '-'}'),
          Text('Model: ${_deviceInfo != null ? _deviceInfo!.model : '-'}'),
          Text('HW: ${_deviceInfo != null ? _deviceInfo!.hw : '-'}  FW: ${_deviceInfo != null ? _deviceInfo!.fw : '-'}'),
          Text('TorqueConv: ${_deviceInfo != null ? _deviceInfo!.torqueConversionFactor.toString() : '-'}'),
          Text('AngleConv: ${_deviceInfo != null ? _deviceInfo!.angleConversionFactor.toString() : '-'}'),
        ]),
      ),
    );
  }

  Widget _buildCountersCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Counters / Summary', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Cycles: ${_countersInfo != null ? _countersInfo!.cycles : '-'}'),
          Text('Overshuts: ${_countersInfo != null ? _countersInfo!.overshuts : '-'}'),
          Text('Higher Overshut: ${_countersInfo != null ? _countersInfo!.higherOvershut : '-'}'),
        ]),
      ),
    );
  }

  Widget _buildMessageArea() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Mensagens', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(_message),
            const SizedBox(height: 12),
            if (_lastTestResults.isNotEmpty) ...[
              const Text('Amostras (preview):', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SizedBox(
                height: 200,
                child: ListView.builder(
                  itemCount: _lastTestResults.length,
                  itemBuilder: (context, index) {
                    final r = _lastTestResults[index];
                    return ListTile(
                      dense: true,
                      title: Text('T: ${r.Torque.toStringAsFixed(3)} Nm  A: ${r.Angle.toStringAsFixed(2)}°'),
                      subtitle: Text('SampleTime: ${r.SampleTime} ms'),
                    );
                  },
                ),
              )
            ]
          ]),
        ),
      ),
    );
  }
}