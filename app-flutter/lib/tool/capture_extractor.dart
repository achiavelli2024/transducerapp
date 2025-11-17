// tools/capture_extractor.dart
// Extrai frames do arquivo capture_raw.bin gerado pelo tcp_capture_proxy.dart
// - Uso:
//    dart run tools/capture_extractor.dart capture_raw.bin c2d_frames.txt
//  (se não passar o segundo argumento, o arquivo de saída será 'c2d_frames.txt')
// - O arquivo de captura usa o formato do proxy:
//    [DIR (1 byte)][LENGTH (4 bytes little-endian)][PAYLOAD (length bytes)]
//   DIR = 0x01 client->device, 0x02 device->client
//
// O extrator vai:
// - ler todos os registros
// - localizar frames entre '[' (0x5B) e ']' (0x5D) dentro de cada payload
// - para registros client->device (dir==1) vai decodificar os bytes internos com latin1
//   e escrever uma linha no arquivo de saída com o frame completo: "[...payload...]"
// - inclui comentários e logging mínimo para iniciantes.
//
// Observações:
// - latin1.decode preserva bytes 0..255 como 1:1, portanto a string escrita corresponderá
//   byte-a-byte para bytes ASCII. Se houver bytes não ASCII, eles serão preservados
//   como caracteres latin1 — para diffs com o C# normalmente funciona bem.
// - Depois de gerar c2d_frames.txt, cole aqui as primeiras 3 linhas ou o resumo para eu comparar.

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run tools/capture_extractor.dart <capture_raw.bin> [out_file]');
    exit(1);
  }
  final inPath = args[0];
  final outPath = (args.length > 1) ? args[1] : 'c2d_frames.txt';
  final inFile = File(inPath);
  if (!await inFile.exists()) {
    print('File not found: $inPath');
    exit(1);
  }

  final bytes = await inFile.readAsBytes();
  final records = _readRecords(bytes);
  print('Records found: ${records.length}');

  final outFile = File(outPath);
  final sink = outFile.openWrite(mode: FileMode.write);
  int totalFrames = 0;
  int c2dFrames = 0;
  int d2cFrames = 0;

  for (var rec in records) {
    final frames = _extractBracketFrames(rec.payload);
    for (var inner in frames) {
      totalFrames++;
      if (rec.dir == 1) {
        c2dFrames++;
        // inner is payload+CRC (inner bytes). We'll decode as latin1 to reconstruct the text frame.
        final frameStr = '[' + latin1.decode(inner) + ']';
        sink.writeln(frameStr);
      } else {
        d2cFrames++;
        // If you want to also store device->client frames, uncomment:
        // final frameStr = '[' + latin1.decode(inner) + ']';
        // sink.writeln('// D->C: ' + frameStr);
      }
    }
  }

  await sink.flush();
  await sink.close();

  print('Total frames (found inside records): $totalFrames');
  print('Client->Device frames written to $outPath : $c2dFrames');
  print('Device->Client frames parsed (not written) : $d2cFrames');
  print('Done. Abra o arquivo $outPath para ver os frames (um por linha).');
}

// ---------- helpers (copiados/compatíveis com proxy format) ----------

class _Record {
  final int dir;
  final Uint8List payload;
  _Record(this.dir, this.payload);
}

List<_Record> _readRecords(Uint8List bytes) {
  final records = <_Record>[];
  int i = 0;
  while (i + 5 <= bytes.length) {
    final dir = bytes[i];
    final len = bytes[i+1] | (bytes[i+2] << 8) | (bytes[i+3] << 16) | (bytes[i+4] << 24);
    i += 5;
    if (i + len > bytes.length) {
      // truncated record; break
      break;
    }
    final payload = bytes.sublist(i, i + len);
    records.add(_Record(dir, payload));
    i += len;
  }
  return records;
}

List<Uint8List> _extractBracketFrames(Uint8List data) {
  final frames = <Uint8List>[];
  int i = 0;
  while (i < data.length) {
    // find '[' (0x5B)
    int start = -1;
    for (; i < data.length; i++) {
      if (data[i] == 0x5B) { start = i; i++; break; }
    }
    if (start < 0) break;
    // find ']'
    int end = -1;
    for (; i < data.length; i++) {
      if (data[i] == 0x5D) { end = i; i++; break; }
    }
    if (end < 0) break;
    if (end - start - 1 >= 1) {
      final inner = data.sublist(start + 1, end); // inner = payload + CRC (last 2 bytes)
      frames.add(Uint8List.fromList(inner));
    }
  }
  return frames;
}