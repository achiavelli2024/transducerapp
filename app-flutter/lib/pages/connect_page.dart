import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../services/tcp_connection.dart';

class ConnectPage extends StatefulWidget {
  const ConnectPage({Key? key}) : super(key: key);

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final _ipController = TextEditingController(text: '192.168.0.100');
  final _portController = TextEditingController(text: '23');
  final TcpConnection _conn = TcpConnection();

  ConnectionStatus _status = ConnectionStatus.disconnected;
  final List<String> _log = [];

  // declarações com tipos genéricos
  StreamSubscription<ConnectionStatus>? _statusSub;
  StreamSubscription<Uint8List>? _dataSub;
  StreamSubscription<Object>? _errSub;

  @override
  void initState() {
    super.initState();

    _statusSub = _conn.statusStream.listen((s) {
      setState(() {
        _status = s;
        _log.add('STATUS: $s');
      });
    });

    _dataSub = _conn.dataStream.listen((bytes) {
      final text = _tryDecode(bytes);
      setState(() {
        _log.add('RX: $text');
      });
    });

    _errSub = _conn.errorStream.listen((err) {
      setState(() {
        _log.add('ERR: $err');
      });
    });
  }

  String _tryDecode(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (e) {
      // fallback para hex
      return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    }
  }

  Future<void> _toggleConnection() async {
    if (_conn.isConnected) {
      await _conn.disconnect();
    } else {
      final ip = _ipController.text.trim();
      final port = int.tryParse(_portController.text.trim()) ?? 23;
      setState(() => _log.add('Tentando conectar em $ip:$port'));
      try {
        await _conn.connect(ip, port);
        setState(() => _log.add('Conectado em $ip:$port'));
      } catch (e) {
        setState(() => _log.add('Falha na conexão: $e'));
      }
    }
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _dataSub?.cancel();
    _errSub?.cancel();
    _conn.dispose();
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Widget _buildStatusChip() {
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

  @override
  Widget build(BuildContext context) {
    final isConnected = _conn.isConnected;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transducer - Conexão TCP'),
        actions: [_buildStatusChip(), const SizedBox(width: 8)],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _ipController,
                decoration: const InputDecoration(labelText: 'IP do transdutor'),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 100,
              child: TextField(
                controller: _portController,
                decoration: const InputDecoration(labelText: 'Porta'),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _toggleConnection,
              child: Text(isConnected ? 'Desconectar' : 'Conectar'),
            ),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(6),
              ),
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _log.length,
                itemBuilder: (context, i) {
                  final item = _log[_log.length - 1 - i]; // reverse
                  return Text(item, style: const TextStyle(fontSize: 12));
                },
              ),
            ),
          ),
        ]),
      ),
    );
  }
}