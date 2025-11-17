// Arquivo: CountersInformation.dart
// Conversão direta de C# -> Dart da classe ITransducers.CountersInformation
// Observações:
// - Mantive os nomes e comportamento do código C# o mais fiel possível.
// - ulong (C#) -> int (Dart usa inteiros de precisão arbitrária).
// - decimal (C#) -> double (em Dart).
// - O método SetInformationByColunms suprimia exceções no C#; aqui também suprimimos
//   exceções para manter exatamente o mesmo comportamento (atribuições realizadas
//   antes de uma exceção permanecem).
// - Incluí métodos auxiliares (fromColumns, fromJson, toJson, toMap) para facilitar uso
//   no Flutter, sem alterar a lógica original.

import 'dart:convert';

class CountersInformation {
  // Propriedades correspondentes ao C#
  int cycles = 0;
  int overshuts = 0;
  double higherOvershut = 0.0;
  int additionalCounter1 = 0;
  int additionalCounter2 = 0;

  CountersInformation();

  // Construtor de conveniência a partir de uma lista de colunas (equivalente ao uso de string[])
  factory CountersInformation.fromColumns(List<String> columns) {
    final info = CountersInformation();
    info.setInformationByColumns(columns);
    return info;
  }

  // Método equivalente ao SetInformationByColunms do C#
  // Recebe uma lista de strings; tenta parsear cada coluna. Qualquer exceção é suprimida.
  void setInformationByColumns(List<String> columns) {
    try {
      if (columns.length > 0) {
        cycles = int.parse(columns[0].trim());
      }
      if (columns.length > 1) {
        overshuts = int.parse(columns[1].trim());
      }
      if (columns.length > 2) {
        // decimal -> double
        higherOvershut = double.parse(columns[2].trim());
      }
      if (columns.length > 3) {
        additionalCounter1 = int.parse(columns[3].trim());
      }
      if (columns.length > 4) {
        additionalCounter2 = int.parse(columns[4].trim());
      }
    } catch (e) {
      // Suprime erros como no código C# original.
      // Em caso de erro, as atribuições já realizadas antes da exceção permanecem.
    }
  }

  // Mantém o nome original com a grafia do C# caso exista código que chame esse nome
  void SetInformationByColunms(List<String> colunas) {
    setInformationByColumns(colunas);
  }

  // Serialização para Map (útil para conversão em JSON ou uso em UI)
  Map<String, dynamic> toMap() {
    return {
      'cycles': cycles,
      'overshuts': overshuts,
      'higherOvershut': higherOvershut,
      'additionalCounter1': additionalCounter1,
      'additionalCounter2': additionalCounter2,
    };
  }

  // Criar a partir de Map
  factory CountersInformation.fromMap(Map<String, dynamic> map) {
    final info = CountersInformation();
    try {
      dynamic _get(Map<String, dynamic> m, String keyVariants) {
        // tenta variações simples (camelCase / PascalCase)
        if (m.containsKey(keyVariants)) return m[keyVariants];
        return null;
      }

      if (map.containsKey('cycles') || map.containsKey('Cycles')) {
        final v = _get(map, map.containsKey('cycles') ? 'cycles' : 'Cycles');
        if (v != null) info.cycles = (v is int) ? v : int.tryParse(v.toString()) ?? info.cycles;
      }

      if (map.containsKey('overshuts') || map.containsKey('Overshuts')) {
        final v = _get(map, map.containsKey('overshuts') ? 'overshuts' : 'Overshuts');
        if (v != null) info.overshuts = (v is int) ? v : int.tryParse(v.toString()) ?? info.overshuts;
      }

      if (map.containsKey('higherOvershut') || map.containsKey('HigherOvershut')) {
        final v = _get(map, map.containsKey('higherOvershut') ? 'higherOvershut' : 'HigherOvershut');
        if (v != null) {
          if (v is double) {
            info.higherOvershut = v;
          } else if (v is int) {
            info.higherOvershut = v.toDouble();
          } else {
            info.higherOvershut = double.tryParse(v.toString()) ?? info.higherOvershut;
          }
        }
      }

      if (map.containsKey('additionalCounter1') || map.containsKey('AdditionalCounter1')) {
        final v = _get(map, map.containsKey('additionalCounter1') ? 'additionalCounter1' : 'AdditionalCounter1');
        if (v != null) info.additionalCounter1 = (v is int) ? v : int.tryParse(v.toString()) ?? info.additionalCounter1;
      }

      if (map.containsKey('additionalCounter2') || map.containsKey('AdditionalCounter2')) {
        final v = _get(map, map.containsKey('additionalCounter2') ? 'additionalCounter2' : 'AdditionalCounter2');
        if (v != null) info.additionalCounter2 = (v is int) ? v : int.tryParse(v.toString()) ?? info.additionalCounter2;
      }
    } catch (e) {
      // Suprime erros para manter comportamento igual ao original
    }
    return info;
  }

  // JSON helpers
  String toJson() => json.encode(toMap());

  factory CountersInformation.fromJson(String source) {
    try {
      final decoded = json.decode(source);
      if (decoded is Map<String, dynamic>) {
        return CountersInformation.fromMap(decoded);
      }
    } catch (e) {
      // Suprime erro e retorna objeto padrão
    }
    return CountersInformation();
  }

  @override
  String toString() {
    return 'CountersInformation(cycles: $cycles, overshuts: $overshuts, higherOvershut: $higherOvershut, '
        'additionalCounter1: $additionalCounter1, additionalCounter2: $additionalCounter2)';
  }
}