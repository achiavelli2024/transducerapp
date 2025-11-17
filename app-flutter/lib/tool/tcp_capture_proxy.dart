// tools/tcp_capture_proxy.dart
// TCP proxy/captor binário simples.
// - Uso: dart run tools/tcp_capture_proxy.dart <listenPort> <remoteHost> <remotePort> <outFile>
// - Ex. Windows (com Dart no PATH):
//     dart run tools/tcp_capture_proxy.dart 5023 192.168.4.1 23 capture_raw.bin
// - Ex. usando o Dart do Flutter (Windows):
//     "C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe" tools/tcp_capture_proxy.dart 5023 192.168.4.1 23 capture_raw.bin
//
// O proxy aceita UMA conexão cliente (se quiser várias, eu adapto).
// Ele grava tudo que entra/saí em <outFile> (modo append) com um pequeno header para saber direção.
// Formato do arquivo: sequence of records:
//   [DIR][4-byte length LE][payload bytes]
//   DIR = 0x01 for client->device (TX from app), 0x02 for device->client (RX to app)
// Isso permite depois separar os fluxos se precisar.
// Também imprime no console resumo em hex (limitado) para debugging.
//
// Observações:
// - Aponte seu app Flutter para localhost:<listenPort> em vez do IP do transdutor.
// - Quando terminar, pressione Ctrl+C no terminal para parar o proxy.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

Future<void> main(List<String> args) async {
  if (args.length < 4) {
    print('Usage: dart run tools/tcp_capture_proxy.dart <listenPort> <remoteHost> <remotePort> <outFile>');
    exit(1);
  }
  final listenPort = int.parse(args[0]);
  final remoteHost = args[1];
  final remotePort = int.parse(args[2]);
  final outFile = args[3];

  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, listenPort);
  print('TCP proxy listening on 127.0.0.1:$listenPort  -> forwarding to $remoteHost:$remotePort');
  print('Raw capture file: $outFile');
  print('Waiting for client connection...');

  await for (final client in server) {
    print('Client connected from ${client.remoteAddress.address}:${client.remotePort}');
    // open connection to remote device
    Socket? device;
    try {
      device = await Socket.connect(remoteHost, remotePort, timeout: Duration(seconds: 5));
      print('Connected to device $remoteHost:$remotePort');
    } catch (e) {
      print('Erro ao conectar ao device: $e');
      client.destroy();
      continue;
    }

    // open file for append in binary
    final file = File(outFile);
    final raf = await file.open(mode: FileMode.append);

    // helper to write a record: dirByte + 4byteLE length + payload
    Future<void> writeRecord(int dir, List<int> data) async {
      final header = Uint8List(5);
      header[0] = dir & 0xFF;
      final len = data.length;
      header[1] = len & 0xFF;
      header[2] = (len >> 8) & 0xFF;
      header[3] = (len >> 16) & 0xFF;
      header[4] = (len >> 24) & 0xFF;
      await raf.writeFrom(header);
      if (len > 0) await raf.writeFrom(data);
      await raf.flush();
    }

    // forward client -> device
    final sub1 = client.listen((data) async {
      // save raw with dir 0x01
      await writeRecord(0x01, data);
      // print small summary
      final snippet = data.length <= 48 ? _toHex(data) : '${_toHex(data.sublist(0,48))} ... (+${data.length - 48} bytes)';
      print('[C->D] ${data.length} bytes: $snippet');
      // forward
      device!.add(data);
    }, onDone: () async {
      print('Client disconnected');
      try { device!.destroy(); } catch (_) {}
      await raf.close();
    }, onError: (e) async {
      print('Client error: $e');
      try { device!.destroy(); } catch (_) {}
      await raf.close();
    });

    // forward device -> client
    final sub2 = device.listen((data) async {
      // save raw with dir 0x02
      await writeRecord(0x02, data);
      final snippet = data.length <= 48 ? _toHex(data) : '${_toHex(data.sublist(0,48))} ... (+${data.length - 48} bytes)';
      print('[D->C] ${data.length} bytes: $snippet');
      client.add(data);
    }, onDone: () async {
      print('Device disconnected');
      try { client.destroy(); } catch (_) {}
      await raf.close();
    }, onError: (e) async {
      print('Device error: $e');
      try { client.destroy(); } catch (_) {}
      await raf.close();
    });

    // if either closes, cancel other
    // keep this connection until closed by either side
  }
}

String _toHex(List<int> data) {
  return data.map((b) => b.toRadixString(16).padLeft(2,'0').toUpperCase()).join(' ');
}