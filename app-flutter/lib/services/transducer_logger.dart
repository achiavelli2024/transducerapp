// lib/services/transducer_logger.dart
// Logger simples e robusto para análise do tráfego TX/RX do PhoenixTransducer.
// - Mantive as APIs previamente usadas (TransducerLogger.configure/log/...)
// - Adicionei uma classe ProtocolFileLogger que replica o comportamento do
//   ProtocolFileLogger C# solicitado:
//     - cria um arquivo único por sessão: Logs\Log-Protocol-YYYYMMdd_HHmmss.Log
//     - grava TX/RX completos (texto + hex) com timestamp yyyy-MM-dd HH:mm:ss.fff
//     - local do arquivo: mesma pasta do .exe/Logs quando em Windows; caso contrário
//       usa ApplicationDocumentsDirectory/transducerapp/logs/ (fallback para Android/iOS).
//
// Linha do tempo (onde estamos / para onde vamos / onde estávamos):
// - Onde estávamos: TransducerLogger gravava apenas em ApplicationDocumentsDirectory.
// - Onde estamos: agora TransducerLogger mantém o comportamento anterior e além disso
//   inicializa o ProtocolFileLogger para gerar um log de protocolo compatível com C#.
// - Para onde vamos: com esse log poderemos comparar lado a lado com o log C# e
//   identificar diferenças de início de leitura (timings / frames TX/RX).
//
// Uso (C#-like):
//   TransducerLogger.configure(); // já chama ProtocolFileLogger.configure()
//   TransducerLogger.logTx('label', framedText);
//   TransducerLogger.logRxBytes('label', buffer, offset, count);
//   ProtocolFileLogger.writeProtocol('TX'|'RX', text, bytes); // opcional direto
//
// Observações:
// - Implementação defensiva: falhas de escrita de log não disparam exceção para o app.
// - Ao empacotar para Windows, a pasta de logs será: <pasta_do_exe>/Logs/Log-Protocol-YYYYMMdd_HHmmss.Log
// - Forneço também ProtocolFileLogger.dispose() para fechar o sink.
// - Não alterei a API usada pelo restante do projeto (connect_page.dart e phoenix_transducer.dart).
//
// Após substituir esse arquivo: flutter clean && flutter pub get && flutter run
//
// Não remova funcionalidades existentes — apenas acrescentei o ProtocolFileLogger.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class TransducerLogger {
  static IOSink? _sink;
  static String? _path;
  static bool _enabled = false;

  // Configure logger - chamar no startup (ex.: ConnectPage.initState)
  // Agora o configure tenta colocar os logs em:
  //  - Windows: mesma pasta do .exe (pasta Logs)
  //  - Outros: ApplicationDocumentsDirectory/transducerapp/logs
  static Future<void> configure({String? fileName}) async {
    try {
      String base;
      try {
        if (Platform.isWindows) {
          // Tentativa de colocar logs na mesma pasta do .exe
          try {
            final exeDir = File(Platform.resolvedExecutable).parent.path;
            base = p.join(exeDir, 'Logs');
          } catch (e) {
            // fallback para app documents
            final dir = await getApplicationDocumentsDirectory();
            base = p.join(dir.path, 'transducerapp', 'logs');
          }
        } else {
          final dir = await getApplicationDocumentsDirectory();
          base = p.join(dir.path, 'transducerapp', 'logs');
        }
      } catch (e) {
        // fallback definitivo
        final dir = await getApplicationDocumentsDirectory();
        base = p.join(dir.path, 'transducerapp', 'logs');
      }

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

      // Também configure o ProtocolFileLogger (cria arquivo protocol-Log no mesmo lugar quando possível)
      await ProtocolFileLogger.configure(preferredBasePath: base);
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
      // dispose protocol logger as well
      await ProtocolFileLogger.dispose();
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
  // Além de gravar no debug log, opcionalmente grava no ProtocolFileLogger
  static void logTx(String label, String framed) {
    logFmt('TX [{0}] -> {1}', [label, framed]);
    try {
      final bytes = utf8.encode(framed);
      logHex('TX BYTES', bytes, 0, bytes.length);
      // também escrever no protocol logger (formato C# style)
      try {
        ProtocolFileLogger.writeProtocol('TX', framed, bytes);
      } catch (_) {}
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
      // também escreve no protocol logger
      try {
        ProtocolFileLogger.writeProtocol('RX', text, buffer.sublist(offset, offset + count));
      } catch (_) {}
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

// --------------------------------------------------------
// ProtocolFileLogger - replica do ProtocolFileLogger C#
// --------------------------------------------------------
class ProtocolFileLogger {
  static final Object _protLock = Object();
  static bool _initialized = false;
  static String? _filePath;
  static IOSink? _sink;

  // Configure manual (optional). preferredBasePath permite o caller (TransducerLogger)
  // informar a pasta onde criar Logs/ (útil para Windows).
  static Future<void> configure({String? preferredBasePath}) async {
    if (_initialized) return;
    try {
      String baseDir;
      if (preferredBasePath != null && preferredBasePath.isNotEmpty) {
        baseDir = preferredBasePath;
      } else {
        // Se estamos no Windows, tente usar a pasta do exe
        try {
          if (Platform.isWindows) {
            baseDir = p.join(File(Platform.resolvedExecutable).parent.path, 'Logs');
          } else {
            final appDoc = await getApplicationDocumentsDirectory();
            baseDir = p.join(appDoc.path, 'transducerapp', 'logs');
          }
        } catch (e) {
          final appDoc = await getApplicationDocumentsDirectory();
          baseDir = p.join(appDoc.path, 'transducerapp', 'logs');
        }
      }

      final dir = Directory(baseDir);
      if (!(await dir.exists())) {
        await dir.create(recursive: true);
      }

      final ts = _timestampForFileName(DateTime.now());
      final fileName = 'Log-Protocol-$ts.Log';
      _filePath = p.join(baseDir, fileName);

      final f = File(_filePath!);
      await f.create(recursive: true);
      // cria o arquivo inicial (registro de início)
      final startLine = '${_formatTimestamp(DateTime.now())} - Protocol log started${Platform.isWindows ? '\r\n' : '\n'}';
      await f.writeAsString(startLine, mode: FileMode.append, encoding: utf8);
      _sink = f.openWrite(mode: FileMode.append, encoding: utf8);
    } catch (ex) {
      try {
        // tentamos não falhar por completo
        print('ProtocolFileLogger init error: $ex');
      } catch (_) {}
      _filePath = null;
      _sink = null;
    } finally {
      _initialized = true;
    }
  }

  // Dispose / fechar arquivo
  static Future<void> dispose() async {
    try {
      if (_sink != null) {
        await _sink!.flush();
        await _sink!.close();
        _sink = null;
      }
    } catch (ex) {
      try {
        print('ProtocolFileLogger.dispose error: $ex');
      } catch (_) {}
    } finally {
      _initialized = false;
      _filePath = null;
    }
  }

  // Escreve uma entrada no arquivo de protocolo. Direction deve ser "TX" ou "RX".
  // text: representação textual (telegrama). raw: bytes (pode ser null).
  static void writeProtocol(String direction, String? text, List<int>? raw) {
    try {
      if (!_initialized) {
        // chamada síncrona para configurar (não-blocante)
        // note: configure() é async, mas aqui podemos chamar e não aguardar; se falhar, não quebra
        configure();
      }
      if (stringIsNullOrEmpty(_filePath)) return;

      final sb = StringBuffer();
      sb.write('${_formatTimestamp(DateTime.now())} [${direction ?? ''}] ${text ?? ''}');
      sb.writeln();

      if (raw != null && raw.isNotEmpty) {
        sb.writeln('HEX: ');
        sb.write(_byteArrayToHexString(raw, ' '));
        sb.writeln();
      }

      // separador visual entre mensagens
      sb.writeln(List.filled(80, '-').join());

      // grava em arquivo de forma thread-safe
      // _sink é um IOSink (assincrono) — escrever é rápido e não deve bloquear UI
      // mas fazemos try/catch defensivo
      try {
        if (_sink != null) {
          _sink!.writeln(sb.toString());
        } else if (_filePath != null) {
          // fallback síncrono
          File(_filePath!).writeAsStringSync(sb.toString(), mode: FileMode.append, encoding: utf8);
        }
      } catch (ex) {
        try {
          print('ProtocolFileLogger.WriteProtocol write error: $ex');
        } catch (_) {}
      }
    } catch (ex) {
      try {
        print('ProtocolFileLogger.WriteProtocol error: $ex');
      } catch (_) {}
    }
  }

  // Helper: converte array de bytes em string hex formatada (16 bytes por linha)
  static String _byteArrayToHexString(List<int> buffer, String separator) {
    if (buffer.isEmpty) return '';
    final sb = StringBuffer();
    for (var i = 0; i < buffer.length; i++) {
      sb.write(buffer[i].toRadixString(16).padLeft(2, '0').toUpperCase());
      if (i < buffer.length - 1) sb.write(separator);
      if ((i + 1) % 16 == 0) sb.writeln();
    }
    return sb.toString();
  }

  // Timestamp format utilizado no arquivo: yyyy-MM-dd HH:mm:ss.fff
  static String _formatTimestamp(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    final ms = dt.millisecond.toString().padLeft(3, '0');
    return '$y-$mo-$d $h:$mi:$s.$ms';
  }

  // Nome do arquivo: YYYYMMdd_HHmmss
  static String _timestampForFileName(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$y$mo$d\_$h$mi$s';
  }

  static bool stringIsNullOrEmpty(String? s) => s == null || s.isEmpty;
}