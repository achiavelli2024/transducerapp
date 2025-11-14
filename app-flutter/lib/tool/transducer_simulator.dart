// Simulador de transdutor (TCP) para testes do app Flutter
// Uso: dart tool/transducer_simulator.dart [porta]
// O simulador responde a comandos entre colchetes: [<payload><CRC>]
// - Usa a mesma lógica makeCRC do TransducerProtocol (portada aqui).
// - Responde a comandos: ID, DI, TQ, ZO, CS, SA (respostas simples plausíveis).
// - Simula fragmentação aleatória para testar parser do app.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

// Copia da implementação makeCRC usada no transducer_protocol.dart
String makeCRC(String cmd) {
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

// Monta frame com colchetes e CRC
String frame(String payload) => '[$payload${makeCRC(payload)}]';

// Gera uma resposta DI (DataInformation) simplificada
String responseDI(String id) {
  // Construção simplificada que mantém posições de campos
  final sn = id.padRight(8, '\x00'); // sn 8
  final model = 'MODEL_SIM'.padRight(32, '\x00'); // 32
  final hw = '0001'; // 4
  final fw = '0001'; // 4
  final type = '01'; // 2 (hex)
  final cap = '000000'; // 6
  final torqueConv = (1000000000).toRadixString(16).padLeft(8, '0');
  final angleConv = (1000).toRadixString(16).padLeft(8, '0');

  // Monta payload com o formato aproximado esperado pelo parser do app
  // Observação: adaptações podem ser necessárias se o parser requerer posições exatas
  final payload = '${id}DI${sn}${model}${hw}${fw}${type}${cap}${torqueConv}${angleConv}';
  return payload;
}

// Gera uma resposta TQ (leitura de torque/angle) com valores randômicos
String responseTQ(String id) {
  final torqueAd = (Random().nextInt(50000) + 1000).toRadixString(16).padLeft(8, '0').toUpperCase();
  final angleAd = (Random().nextInt(3600)).toRadixString(16).padLeft(8, '0').toUpperCase();
  final payload = '${id}TQ$torqueAd$angleAd';
  return payload;
}

Future<void> handleClient(Socket client) async {
  print('Client connected: ${client.remoteAddress.address}:${client.remotePort}');
  final buffer = <int>[];
  client.listen((data) async {
    buffer.addAll(data);
    var s = utf8.decode(buffer, allowMalformed: true);

    // Extrai frames completos recebidos
    final rxFrames = <String>[];
    while (true) {
      final start = s.indexOf('[');
      final end = s.indexOf(']', start + 1);
      if (start >= 0 && end > start) {
        final frame = s.substring(start + 1, end); // payload+crc
        rxFrames.add(frame);
        s = s.substring(end + 1);
      } else {
        break;
      }
    }

    // Mantém restos não processados no buffer
    buffer
      ..clear()
      ..addAll(utf8.encode(s));

    for (final f in rxFrames) {
      if (f.length < 2) continue;
      final payload = f.substring(0, f.length - 2);
      final crc = f.substring(f.length - 2);
      print('RX payload: $payload crc:$crc from ${client.remoteAddress.address}');
      String id = '000000000000';
      if (payload.length >= 12) id = payload.substring(0, 12);
      String com = '';
      if (payload.length >= 14) com = payload.substring(12, 14);

      String respPayload = '';
      if (com == 'ID') {
        respPayload = '${id}ID';
      } else if (com == 'DI') {
        respPayload = responseDI(id);
      } else if (com == 'TQ') {
        respPayload = responseTQ(id);
      } else if (com == 'ZO') {
        respPayload = '${id}ZO01';
      } else if (com == 'CS') {
        respPayload = '${id}CS00';
      } else if (com == 'SA') {
        respPayload = '${id}SA00';
      } else {
        final cmd = com.isNotEmpty ? com : 'OK';
        respPayload = '${id}${cmd}00';
      }

      final framed = frame(respPayload);

      // Simula fragmentação aleatória para testar robustez do parser
      if (Random().nextBool()) {
        final idx = (framed.length / 2).floor();
        client.add(utf8.encode(framed.substring(0, idx)));
        await Future.delayed(Duration(milliseconds: 40));
        client.add(utf8.encode(framed.substring(idx)));
      } else {
        client.add(utf8.encode(framed));
      }
      print('TX -> $framed');
    }
  }, onDone: () {
    print('Client disconnected ${client.remoteAddress.address}');
  }, onError: (e) {
    print('Client error: $e');
  });
}

Future<void> main(List<String> args) async {
  final port = args.isNotEmpty ? int.tryParse(args[0]) ?? 2323 : 2323;
  final server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
  print('Transducer simulator listening on 0.0.0.0:$port');
  await for (final client in server) {
    handleClient(client);
  }
}