// tools/frame_diff.dart
// Compara dois arquivos de frames (um frame por linha, formato "[...payload...]").
// Uso:
//   dart run tools/frame_diff.dart c2d_csharp.txt c2d_flutter.txt
//
// Saída:
// - mostra quantas linhas em cada arquivo
// - mostra as primeiras N diferenças com contexto e um resumo final
//
// Esta ferramenta é apenas para diagnóstico: não altera seu código.

import 'dart:io';
import 'dart:convert';

void main(List<String> args) async {
  if (args.length < 2) {
    print('Usage: dart run tools/frame_diff.dart <c2d_csharp.txt> <c2d_flutter.txt>');
    exit(1);
  }
  final fileA = File(args[0]);
  final fileB = File(args[1]);
  if (!await fileA.exists()) { print('File not found: ${fileA.path}'); exit(1); }
  if (!await fileB.exists()) { print('File not found: ${fileB.path}'); exit(1); }

  final linesA = (await fileA.readAsLines()).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  final linesB = (await fileB.readAsLines()).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  print('A (${fileA.path}) lines: ${linesA.length}');
  print('B (${fileB.path}) lines: ${linesB.length}');
  print('');

  final maxI = (linesA.length > linesB.length) ? linesA.length : linesB.length;
  int diffs = 0;
  final maxShow = 50; // máximo diferenças mostradas
  for (var i = 0; i < maxI; i++) {
    final a = i < linesA.length ? linesA[i] : '<MISSING>';
    final b = i < linesB.length ? linesB[i] : '<MISSING>';
    if (a != b) {
      diffs++;
      if (diffs <= maxShow) {
        print('--- Diff #$diffs at line ${i+1} ---');
        print('A: $a');
        print('B: $b');
        // also show hex-bytes for payload (strip surrounding brackets if present)
        final aInner = _stripBrackets(a);
        final bInner = _stripBrackets(b);
        print('A hex: ${_toHex(aInner)}');
        print('B hex: ${_toHex(bInner)}');
        print('');
      }
    }
  }

  print('Total differences: $diffs');
  if (diffs > maxShow) print('... showed first $maxShow diffs');
  if (diffs == 0) print('No differences found (line-by-line exact match).');
}

String _stripBrackets(String s) {
  if (s.startsWith('[') && s.endsWith(']')) return s.substring(1, s.length - 1);
  return s;
}

String _toHex(String s) {
  try {
    final bytes = latin1.encode(s);
    return bytes.map((b) => b.toRadixString(16).padLeft(2,'0').toUpperCase()).join(' ');
  } catch (e) {
    return '<cannot-encode>';
  }
}