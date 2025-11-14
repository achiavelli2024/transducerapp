// lib/services/transducer_logger.dart
// Logger simples e robusto para análise do tráfego TX/RX do PhoenixTransducer.
// - Grava mensagens e dumps hex no ApplicationDocumentsDirectory/transducerapp/logs/
// - Métodos estáticos: configure(), log(), logTx(), logRxBytes(), logError(), dispose()
// - Não lança exceções para o chamador; grava em arquivo e também printa no console.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class TransducerLogger {
  static IOSink? _sink;
  static String? _path;
  static bool _enabled = false;

  // Configure logger - chamar no startup (ex.: ConnectPage.initState)
  static Future<void> configure({String? fileName}) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final base = p.join(dir.path, 'transducerapp', 'logs');
      final dirF = Directory(base);
      if (!(await dirF.exists())) {
        await dirF.create(recursive: true);
      }
      final fname = fileName ?? 'transducer_debug.log';
      _path = p.join(base, fname);
      final f = File(_path!);
      await f.create(recursive: true);
      _sink = f.openWrite(mode: FileMode.append, encoding: utf8);
      _enabled = true;
      log('TransducerLogger configured path=$_path');
    } catch (ex) {
      _safePrint('TransducerLogger.configure failed: $ex');
      _enabled = false;
    }
  }

  // Close sink on dispose
  static Future<void> dispose() async {
    try {
      if (_sink != null) {
        await _sink!.flush();
        await _sink!.close();
        _sink = null;
      }
      _enabled = false;
    } catch (ex) {
      _safePrint('TransducerLogger.dispose error: $ex');
    }
  }

  // Basic textual log with timestamp
  static void log(String msg) {
    final line = '${_now()} $msg';
    _append(line);
  }

  // Log formatted (like LogFmt)
  static void logFmt(String fmt, List<Object?> args) {
    try {
      var s = fmt;
      for (var i = 0; i < args.length; i++) {
        s = s.replaceAll('{' + i.toString() + '}', args[i]?.toString() ?? 'null');
      }
      log(s);
    } catch (ex) {
      log('logFmt error: $ex');
    }
  }

  // Log TX: labeled framed ascii and hex
  static void logTx(String label, String framed) {
    logFmt('TX [{0}] -> {1}', [label, framed]);
    try {
      final bytes = utf8.encode(framed);
      logHex('TX BYTES', bytes, 0, bytes.length);
    } catch (ex) {
      log('logTx encode error: $ex');
    }
  }

  // Log RX chunk (bytes) and text
  static void logRxBytes(String label, List<int> buffer, int offset, int count) {
    logFmt('RX [{0}] bytes={1}', [label, count]);
    logHex('RX BYTES', buffer, offset, count);
    try {
      final text = utf8.decode(buffer.sublist(offset, offset + count), allowMalformed: true);
      logFmt('RX [{0}] text: {1}', [label, text]);
    } catch (ex) {
      // ignore
    }
  }

  // Hex dump writer (formatado)
  static void logHex(String title, List<int> buffer, int offset, int count) {
    try {
      if (buffer.isEmpty || count <= 0) {
        _safePrint('logHex nothing to write for $title');
        return;
      }
      final max = (offset + count).clamp(0, buffer.length);
      final sb = StringBuffer();
      sb.writeln('${_now()} LogHex: $title - $count bytes');
      for (var i = offset; i < max; i += 16) {
        final lineLen = (max - i) < 16 ? (max - i) : 16;
        sb.write('${i.toRadixString(16).padLeft(8, '0').toUpperCase()}  ');
        for (var j = 0; j < 16; j++) {
          if (j < lineLen) {
            sb.write('${buffer[i + j].toRadixString(16).padLeft(2, '0').toUpperCase()} ');
          } else {
            sb.write('   ');
          }
        }
        sb.write(' ');
        for (var j = 0; j < lineLen; j++) {
          final b = buffer[i + j];
          final ch = (b >= 32 && b <= 126) ? String.fromCharCode(b) : '.';
          sb.write(ch);
        }
        sb.writeln();
      }
      _append(sb.toString());
    } catch (ex) {
      _safePrint('logHex failed: $ex');
    }
  }

  // Log exception with optional context
  static void logException(Object ex, [String? context]) {
    final ctx = context != null ? ' [$context]' : '';
    log('EXCEPTION$ctx: $ex');
  }

  // Append text to sink and print to console (defensive)
  static void _append(String text) {
    _safePrint(text);
    try {
      if (_enabled && _sink != null) {
        _sink!.writeln(text);
      } else if (_path != null) {
        // fallback: append to file
        File(_path!).writeAsStringSync(text + '\n', mode: FileMode.append, encoding: utf8);
      }
    } catch (ex) {
      _safePrint('TransducerLogger append error: $ex');
    }
  }

  static String _now() => DateTime.now().toIso8601String();
  static void _safePrint(Object? o) {
    try {
      // prints to IDE console
      print(o);
    } catch (_) {}
  }
}