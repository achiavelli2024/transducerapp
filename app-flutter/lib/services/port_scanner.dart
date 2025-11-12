import 'dart:io';
import 'dart:async';

/// Varredura simples de portas TCP. Retorna lista de portas que aceitaram conexão.
Future<List<int>> scanPorts(String host, List<int> ports,
    {Duration timeout = const Duration(seconds: 2)}) async {
  final List<int> open = [];
  final futures = ports.map((port) async {
    try {
      final sock = await Socket.connect(host, port).timeout(timeout);
      sock.destroy();
      open.add(port);
    } catch (_) {
      // fechado / timeout / recusa
    }
  }).toList();
  await Future.wait(futures);
  return open..sort();
}

void main() async {
  final host = '192.168.4.1';
  // portas comuns para testar. Adicione outras se quiser.
  final portsToTest = [23, 2323, 80, 8080, 502, 69, 21, 22, 443, 9000];
  print('Scanning $host ...');
  final open = await scanPorts(host, portsToTest, timeout: Duration(seconds: 3));
  print('Open ports: $open');
}