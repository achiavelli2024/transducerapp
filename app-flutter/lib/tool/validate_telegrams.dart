// tools/validate_telegrams.dart
// Versão atualizada: lê arquivo como bytes e extrai frames entre '[' e ']' byte-a-byte.
// Suporta blocos GD binários (não-textuais) e compara CRC corretamente.
//
// Uso:
// 1) Coloque telnet_dump.txt com seus frames (pode conter frames binários).
// 2) No Windows (com dart no PATH) rode:
//      dart run tools/validate_telegrams.dart telnet_dump.txt
//    Ou use o Dart que vem no Flutter (exemplo Windows):
//      "C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe" tools\validate_telegrams.dart telnet_dump.txt
//
// O script vai:
// - procurar todos os blocos entre 0x5B '[' e 0x5D ']'
// - para cada frame extrair payloadBytes = inner[0..len-3] e recvCrcBytes = inner[len-2,len-1]
// - recalcular CRC com o mesmo algoritmo usado no cliente Dart e comparar com CRC recebido
// - imprimir payload como ASCII se for majoritariamente imprimível, caso contrário mostra hex
//
// Não altera nada no seu projeto; apenas leitura offline do dump.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run tools/validate_telegrams.dart <telnet_dump.txt>');
    exit(1);
  }
  final path = args[0];
  final file = File(path);
  if (!await file.exists()) {
    print('File not found: $path');
    exit(1);
  }

  final bytes = await file.readAsBytes();
  final frames = <Uint8List>[];

  // encontra pares de colchetes '['(0x5B) ... ']'(0x5D)
  int i = 0;
  while (i < bytes.length) {
    // procura '['
    int start = -1;
    for (; i < bytes.length; i++) {
      if (bytes[i] == 0x5B) { // '['
        start = i;
        i++;
        break;
      }
    }
    if (start < 0) break;
    // procura ']'
    int end = -1;
    for (; i < bytes.length; i++) {
      if (bytes[i] == 0x5D) { // ']'
        end = i;
        i++;
        break;
      }
    }
    if (end < 0) break; // frame não fechado; descarta
    // extrai frame incluindo [ ]
    final frame = Uint8List.fromList(bytes.sublist(start, end + 1));
    frames.add(frame);
  }

  print('Frames found: ${frames.length}');
  int idx = 0;
  for (final framed in frames) {
    idx++;
    // framed is bytes including '[' and ']'
    if (framed.length < 5) {
      print('[$idx] Frame too short (ignored): ${_bytesToHex(framed)}');
      continue;
    }
    // inner bytes = framed[1 .. len-2]
    final inner = framed.sublist(1, framed.length - 1);
    if (inner.length < 3) {
      print('[$idx] inner too short (ignored) : ${_bytesToHex(inner)}');
      continue;
    }

    // last two bytes of inner are CRC ASCII chars
    final recvCrcBytes = inner.sublist(inner.length - 2);
    final payloadBytes = inner.sublist(0, inner.length - 2);

    // calcula CRC
    final calcCrcBytes = makeCRCBytes(payloadBytes); // returns two ASCII bytes as ints

    final recvCrcStr = _bytesToPrintableAsciiOrHex(recvCrcBytes);
    final calcCrcStr = String.fromCharCodes(calcCrcBytes);

    final crcOk = (recvCrcBytes.length == 2 && calcCrcBytes.length == 2 &&
        recvCrcBytes[0] == calcCrcBytes[0] && recvCrcBytes[1] == calcCrcBytes[1]);

    print('--- Frame #$idx ---');
    print('Framed (hex): ${_bytesToHex(framed)}');
    // show payload as ascii if >50% printable; else hex
    final payloadPrintable = _isMostlyPrintable(payloadBytes);
    if (payloadPrintable) {
      try {
        final s = latin1.decode(payloadBytes);
        print('Payload (ascii): "$s"');
      } catch (_) {
        print('Payload (hex): ${_bytesToHex(payloadBytes)}');
      }
    } else {
      print('Payload (hex): ${_bytesToHex(payloadBytes)}');
    }
    print('Payload len: ${payloadBytes.length} bytes');
    print('CRC recv bytes: ${_bytesToHex(recvCrcBytes)} -> "${_safeAscii(recvCrcBytes)}"');
    print('CRC calc bytes: ${_bytesToHex(calcCrcBytes)} -> "${String.fromCharCodes(calcCrcBytes)}"');
    print('CRC match: ${crcOk ? "OK" : "MISMATCH"}');

    if (!crcOk) {
      // extra info to help debug
      final show = payloadBytes.length > 32 ? payloadBytes.sublist(0, 32) : payloadBytes;
      print('  -> payload first bytes: ${_bytesToHex(show)}');
    }
  }
}

// utils

String _bytesToHex(List<int> bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
}

bool _isPrintableByte(int b) => b >= 32 && b < 127;

bool _isMostlyPrintable(Uint8List bytes) {
  if (bytes.isEmpty) return true;
  int printable = 0;
  for (var b in bytes) if (_isPrintableByte(b)) printable++;
  return printable / bytes.length >= 0.6;
}

String _bytesToPrintableAsciiOrHex(List<int> bytes) {
  try {
    final s = latin1.decode(bytes);
    return s;
  } catch (_) {
    return _bytesToHex(bytes);
  }
}

String _safeAscii(List<int> bytes) {
  try {
    return latin1.decode(bytes);
  } catch (_) {
    return _bytesToHex(bytes);
  }
}

// CRC algoritmo igual ao do cliente Dart (opera sobre bytes do payload)
// Retorna 2 bytes ASCII (int values)
List<int> makeCRCBytes(List<int> payload) {
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