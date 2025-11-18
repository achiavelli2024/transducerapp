import 'dart:async';
import 'package:flutter/material.dart';
//import '../models/data_information.dart';


import '../services/phoenix_transducer.dart';
import '../services/transducer_logger.dart'; // logger defensivo

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
  DataResult? _lastResult; // valor em tempo real (TQ)
  DataResult? _frozenResult; // valor congelado / final (FR) - automatico
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

  // Linha do tempo (curta) mostrada no app/log:
  // - Antes: conectar -> startCommunication (ID/DI/DS)
  // - Ação: Iniciar leitura (InitRead manual)
  // - Depois: StartReadData -> TQ polling e GD blocos
  //
  // Use _message e logs para acompanhar cada passo.

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

    // TQ = valor em tempo real; atualiza label "Última Leitura"
    _transducer!.onDataResult = (DataResult dr) {
      setState(() {
        _lastResult = dr;
      });
    };

    // TesteResult = lista de amostras (GD/FR). Agora com auto-congelamento:
    //  - se houver FR -> usa FR
    //  - se NÃO houver FR -> escolhe a amostra com maior torque absoluto (heurística)
    _transducer!.onTesteResult = (List<DataResult> results) {
      setState(() {
        _lastTestResults = results;
        // 1) procura FR explícito
        DataResult? fr;
        try {
          fr = results.firstWhere((r) => (r.Type ?? '').toUpperCase() == 'FR', orElse: () => DataResult()..Type = '');
          if (fr.Type == '') fr = null;
        } catch (_) {
          fr = null;
        }

        if (fr != null) {
          // FR encontrado: atualiza frozen automaticamente
          _frozenResult = fr;
          _message = 'Resultado final (FR) recebido automaticamente';
        } else {
          // Nenhum FR explícito: heurística -> escolher maior torque absoluto
          if (results.isNotEmpty) {
            DataResult best = results[0];
            double bestAbs = _absTorque(best);
            for (var r in results) {
              double a = _absTorque(r);
              if (a > bestAbs) {
                best = r;
                bestAbs = a;
              }
            }
            // Atualiza frozen com a melhor amostra detectada
            _frozenResult = best;
            _message = 'Resultado final estimado (maior torque) definido automaticamente';
          } else {
            // lista vazia
            _message = 'TesteResult recebido (vazio)';
          }
        }
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
        _message = 'Conectado';
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
        _frozenResult = null;
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

  // ------------------------------
  // INICIALIZAÇÃO DE LEITURA (ALINHADO AO C#)
  // ------------------------------
  // Implementação: enviar comandos via setters e NÃO aguardar o ACK de SA.
  // Isso replica o InitRead() C# que chama SetTestParameter(...) e Thread.Sleep(100)
  // antes de chamar StartReadData().
  Future<void> _initReadSequence() async {
    if (_transducer == null) return;

    setState(() {
      _message = 'Preparando parâmetros (modo C#) e iniciando leitura...';
    });

    try {
      TransducerLogger.log('InitRead(C#-style): START sequence (manual)');

      // 1) Zero torque
      TransducerLogger.log('InitRead(C#-style): SetZeroTorque');
      _transducer!.setZeroTorque();
      // delay idêntico ao C#
      await Future.delayed(const Duration(milliseconds: 10));

      // 2) Zero angle
      TransducerLogger.log('InitRead(C#-style): SetZeroAngle');
      _transducer!.setZeroAngle();
      await Future.delayed(const Duration(milliseconds: 10));

      // 3) Click-wrench params (CS) - usar os mesmos valores do C# (30,30,20)
      TransducerLogger.log('InitRead(C#-style): SetTestParameter_ClickWrench(30,30,20)');
      _transducer!.setTestParameterClickWrench(30, 30, 20);
      // pequeno delay para ordenação (não bloqueante)
      await Future.delayed(const Duration(milliseconds: 5));

      // 4) Acquisition config (SA + SB/SC) - replicar os valores do C# conforme logs
      TransducerLogger.log('InitRead(C#-style): SetTestParameter (full) -> SA/SB/SC (configurar valores)');
      // IMPORTANTE: timeoutEndMs = 400 (0x0190) conforme log do C#
      // timeStepMs = 1, filterFrequency = 500, angleTarget = 100, delays 50ms etc.
      await _transducer!.setTestParameter(
        null, // DataInformation (não precisa enviar aqui)
        TesteType.TorqueOnly,
        ToolType.ToolType1,
        4.0,   // nominalTorque
        2.0,   // threshold inicial (C# log)
        thresholdEnd: 0.5,
        timeoutEndMs: 400, // crucial: usar 400 conforme C#
        timeStepMs: 1,
        filterFrequency: 500,
        direction: eDirection.CW,
        torqueTarget: 4.0,
        torqueMin: 2.0,
        torqueMax: 6.0,
        angleTarget: 100.0,
        angleMin: 10.0,
        angleMax: 300.0,
        delayToDetectFirstPeakMs: 50,
        timeToIgnoreNewPeakAfterFinalThresholdMs: 50,
      );
      // Note: setTestParameter é async, aguardamos para garantir valores aplicados internamente
      await Future.delayed(const Duration(milliseconds: 5));

      // 5) Aguarde 100ms (conforme C#) e então iniciar leitura (StartReadData)
      TransducerLogger.log('InitRead(C#-style): sleep 100ms (como C#) e StartReadData');
      await Future.delayed(const Duration(milliseconds: 100));

      _transducer!.startReadData();
      TransducerLogger.log('InitRead(C#-style): StartReadData called');

      setState(() {
        _message = 'Sequência InitRead (modo C#) enviada. Leitura iniciada (StartReadData).';
      });
    } catch (e, st) {
      TransducerLogger.logException(e, '_initReadSequence (C#-style)');
      setState(() {
        _message = 'Erro InitRead (C#-style): $e';
      });
    }
  }//aqui

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

  // Clear frozen value (manual)
  void _clearFrozen() {
    setState(() {
      _frozenResult = null;
      _message = 'Valor congelado limpo manualmente';
    });
  }

  // Heurística: retorna torque absoluto (tratando nulls)
  double _absTorque(DataResult r) {
    try {
      return r.Torque.abs();
    } catch (_) {
      return 0.0;
    }
  }

  // UI builder
  @override
  Widget build(BuildContext context) {
    // Usamos SingleChildScrollView para garantir que em telas pequenas nada seja cortado.
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transducer - Conexão TCP'),
        actions: [
          Padding(padding: const EdgeInsets.all(8.0), child: _statusChip()),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTopControls(),
              const SizedBox(height: 8),
              _buildResultCards(), // mostra real-time + frozen
              const SizedBox(height: 8),
              _buildInfoCard(),
              const SizedBox(height: 8),
              _buildCountersCard(),
              const SizedBox(height: 8),
              _buildMessageArea(), // mensagens e amostras
              const SizedBox(height: 16),
              Center(child: Text('Observação: foco apenas TCP (WiFi). Parser e dispatcher permanecem sem alterações.', style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
            ],
          ),
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

  Widget _buildTopControls() {
    // Top controls com TextFields e botões (Wrap para se adaptar em pequenas larguras)
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(children: [
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





          // Use Wrap para evitar overflow de botões em telas estreitas
          // substitua o seu Wrap atual por este (coloque no mesmo lugar)
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              ElevatedButton(
                onPressed: () {
                  TransducerLogger.log('Botão Conectar/Desconectar pressionado pelo usuário');
                  _toggleConnection();
                },
                child: Text((_status == ConnectionStatus.connected || _status == ConnectionStatus.connecting) ? 'Desconectar' : 'Conectar'),
              ),
              ElevatedButton(
                onPressed: (_status == ConnectionStatus.connected) ? _requestInfoImmediate : null,
                child: const Text('Request Info'),
              ),

              // --- BOTÃO INICIAR LEITURA instrumentado com logs ---
              ElevatedButton(
                // se conectado, habilita o botão; closure async para aguardar _initReadSequence
                onPressed: (_status == ConnectionStatus.connected)
                    ? () async {
                  // 1) log do evento UI (apenas informativo)
                  TransducerLogger.log('Botão Iniciar Leitura pressionado pelo usuário');

                  // 2) atualizar UI para feedback (opcional)
                  setState(() {
                    _message = 'Iniciando sequência InitRead...';
                  });

                  try {
                    // 3) chamar a sequência (a própria função faz logs internos também)
                    await _initReadSequence();

                    // 4) log de sucesso (a função interna também já registra, mas aqui marcamos o retorno)
                    TransducerLogger.log('InitRead sequence (chamada do botão) concluída/mandada com sucesso');

                    // 5) atualizar UI novamente (opcional)
                    setState(() {
                      _message = 'Sequência InitRead enviada';
                    });
                  } catch (e, st) {
                    // 6) log de exceção com contexto
                    TransducerLogger.logException(e, 'Erro ao executar _initReadSequence (via botão)');
                    // também registra stack trace no debug log
                    TransducerLogger.log('StackTrace: $st');

                    setState(() {
                      _message = 'Erro ao iniciar leitura: $e';
                    });
                  }
                }
                    : null,
                child: const Text('Iniciar Leitura'),
              ),
              // ----------------------------------------------------

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




        ]),
      ),
    );
  }

  Widget _buildResultCards() {
    // Em telas largas mostramos duas colunas; em telas pequenas empilhamos.
    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth > 600;
      if (isWide) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _cardLastReading()),
            const SizedBox(width: 8),
            Expanded(child: _cardFrozenReading()),
          ],
        );
      } else {
        return Column(
          children: [
            _cardLastReading(),
            const SizedBox(height: 8),
            _cardFrozenReading(),
          ],
        );
      }
    });
  }

  Widget _cardLastReading() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Última Leitura (em tempo real)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Torque: ${_lastResult != null ? _lastResult!.Torque.toStringAsFixed(3) + " Nm" : "-"}', style: const TextStyle(fontSize: 16)),
          Text('Ângulo: ${_lastResult != null ? _lastResult!.Angle.toStringAsFixed(3) + " °" : "-"}', style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          Text('Amostras de último teste: ${_lastTestResults.length}'),
        ]),
      ),
    );
  }

  Widget _cardFrozenReading() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Valor Congelado (Resultado Final - FR)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Torque: ${_frozenResult != null ? _frozenResult!.Torque.toStringAsFixed(3) + " Nm" : "-"}', style: const TextStyle(fontSize: 16)),
          Text('Ângulo: ${_frozenResult != null ? _frozenResult!.Angle.toStringAsFixed(3) + " °" : "-"}', style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          Row(children: [
            ElevatedButton(
              onPressed: _frozenResult != null ? _clearFrozen : null,
              child: const Text('Limpar Congelado'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _lastResult != null
                  ? () {
                // snapshot "congelar agora"
                setState(() {
                  _frozenResult = _lastResult;
                  _message = 'Congelado manual (snapshot)';
                });
              }
                  : null,
              child: const Text('Congelar Agora'),
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
          Text('Model: ${_device_info_safe()}'),
          Text('HW: ${_device_fw_safe()}  FW: ${_deviceInfo != null ? _deviceInfo!.fw : '-'}'),
          Text('TorqueConv: ${_deviceInfo != null ? _deviceInfo!.torqueConversionFactor.toString() : '-'}'),
          Text('AngleConv: ${_deviceInfo != null ? _deviceInfo!.angleConversionFactor.toString() : '-'}'),
        ]),
      ),
    );
  }

  String _device_info_safe() {
    try {
      return _deviceInfo != null ? _deviceInfo!.model : '-';
    } catch (_) {
      return '-';
    }
  }

  String _device_fw_safe() {
    try {
      return _deviceInfo != null ? _deviceInfo!.hw : '-';
    } catch (_) {
      return '-';
    }
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
                    subtitle: Text('SampleTime: ${r.SampleTime} ms  Type: ${r.Type ?? ""}'),
                  );
                },
              ),
            )
          ] else ...[
            const SizedBox(height: 8),
            const Text('Nenhuma amostra disponível', style: TextStyle(color: Colors.grey))
          ]
        ]),
      ),
    );
  }
}