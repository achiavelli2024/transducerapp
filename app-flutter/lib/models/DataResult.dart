// Arquivo: DataResult.dart
// Conversão direta de C# -> Dart da classe ITransducers.DataResult
//
// Observações:
// - Mantive o comportamento do C# o mais fiel possível, incluindo índices de colunas
//   e suprimindo exceções onde o código original também as suprimia.
// - Tipos: decimal -> double, DateTime -> DateTime (Dart).
// - Preservado o nome original dos métodos com a grafia exata do C# e adicionei versões
//   com convenção lowerCamelCase para facilidade de uso em Dart.
// - Incluí helpers (toMap/fromMap/toJson/fromJson) e um método utilitário de arredondamento.
// - Comentários em português explicando cada parte.

import 'dart:convert';

class DataResult {
  int thresholdDir = 0;
  int resultDir = 0;

  String type = '';
  double torque = 0.0;
  double angle = 0.0;

  int sampleTime = 0;

  DateTime date;
  double batteryLevel = 0.0;

  DataResult() : date = DateTime.now();

  // Construtor de conveniência
  DataResult.withValues({
    this.thresholdDir = 0,
    this.resultDir = 0,
    this.type = '',
    this.torque = 0.0,
    this.angle = 0.0,
    this.sampleTime = 0,
    DateTime? date,
    this.batteryLevel = 0.0,
  }) : date = date ?? DateTime.now();

  // Helper: arredonda double com `places` casas decimais
  double _roundTo(double value, int places) {
    return double.parse(value.toStringAsFixed(places));
  }

  // --- Métodos de parsing traduzidos do C# ---
  // Observação: os métodos replicam a lógica do C# fielmente (mesmos índices, mesmo comportamento de supressão de exceções).

  // Equivalente a SetDataCalibrationByColunms(string[] Colunas, decimal FatAD)
  void setDataCalibrationByColumns(List<String> columns, double fatAD) {
    int _angleInt = 0;
    double _dAngle = 0.0;
    double _torque = 0.0;
    double _batteryLevel = 0.0;

    // Mesmo teste do C# (retorna se tiver menos de 4 colunas)
    if (columns.length < 4) return;

    type = "CA";

    try {
      // Tenta parsear Colunas[4] como decimal (double)
      // Nota: pode lançar se index fora do range; o bloco try/catch suprime exceções (como no C#)
      final raw = columns[4];
      final parsed = double.tryParse(raw);
      if (parsed != null) {
        _dAngle = parsed;
        angle = _roundTo(_dAngle, 4);
      }
    } catch (e) {
      // Suprime erro (comportamento idêntico ao C# original)
    }

    if (_dAngle == 0.0) {
      try {
        final parsedInt = int.tryParse(columns[4]);
        if (parsedInt != null) {
          _angleInt = parsedInt;
          angle = _angleInt.toDouble();
        }
      } catch (e) {
        // Suprime
      }
    }

    // Se o valor, convertido para int, for 32640, zera o ângulo (comportamento do C#)
    try {
      if (angle.toInt() == 32640) {
        angle = 0.0;
      }
    } catch (e) {
      // Suprime
    }

    try {
      final tRaw = columns[2].trim();
      final tParsed = double.tryParse(tRaw);
      if (tParsed != null) _torque = tParsed;
    } catch (e) {
      // Suprime
    }

    if (fatAD > 0) {
      try {
        torque = _roundTo(_torque / fatAD, 4);
      } catch (e) {
        // Suprime
      }
    }

    try {
      final bRaw = columns[5].trim();
      final bParsed = double.tryParse(bRaw);
      if (bParsed != null) _batteryLevel = bParsed;
      // No C#: BatteryLevel = _BatteryLevel / 100;
      batteryLevel = _batteryLevel / 100.0;
    } catch (e) {
      // Suprime
    }
  }

  // Mantém o nome original do C# com grafia exata
  void SetDataCalibrationByColunms(List<String> Colunas, double FatAD) {
    setDataCalibrationByColumns(Colunas, FatAD);
  }

  // Equivalente a SetDataTestVerificationByColunms(string[] Colunas, decimal FatAD)
  void setDataTestVerificationByColumns(List<String> columns, double fatAD) {
    int _angleInt = 0;
    double _dAngle = 0.0;
    double _torque = 0.0;

    if (columns.length < 6) return;

    type = "TV";

    try {
      final raw = columns[5];
      final parsed = double.tryParse(raw);
      if (parsed != null) {
        _dAngle = parsed;
        angle = _roundTo(_dAngle, 4);
      }
    } catch (e) {
      // Suprime
    }

    if (_dAngle == 0.0) {
      try {
        final parsedInt = int.tryParse(columns[5]);
        if (parsedInt != null) {
          _angleInt = parsedInt;
          angle = _angleInt.toDouble();
        }
      } catch (e) {
        // Suprime
      }
    }

    try {
      if (angle.toInt() == 32640) {
        angle = 0.0;
      }
    } catch (e) {
      // Suprime
    }

    try {
      final tRaw = columns[2].trim();
      final tParsed = double.tryParse(tRaw);
      if (tParsed != null) _torque = tParsed;
    } catch (e) {
      // Suprime
    }

    if (fatAD > 0) {
      try {
        torque = _roundTo(_torque / fatAD, 4);
      } catch (e) {
        // Suprime
      }
    }
  }

  // Mantém nome original do C#
  void SetDataTestVerificationByColunms(List<String> Colunas, double FatAD) {
    setDataTestVerificationByColumns(Colunas, FatAD);
  }

  // Equivalente a SetDataFinalResultByColunms(string[] Colunas, decimal FatAD)
  void setDataFinalResultByColumns(List<String> columns, double fatAD) {
    int _angleInt = 0;
    double _dAngle = 0.0;
    double _torque = 0.0;

    if (columns.length < 2) return;

    type = "FR";

    try {
      final raw = columns[2];
      final parsed = double.tryParse(raw);
      if (parsed != null) {
        _dAngle = parsed;
        angle = _roundTo(_dAngle, 4);
      }
    } catch (e) {
      // Suprime
    }

    if (_dAngle == 0.0) {
      try {
        final parsedInt = int.tryParse(columns[2]);
        if (parsedInt != null) {
          _angleInt = parsedInt;
          angle = _angleInt.toDouble();
        }
      } catch (e) {
        // Suprime
      }
    }

    try {
      if (angle.toInt() == 32640) {
        angle = 0.0;
      }
    } catch (e) {
      // Suprime
    }

    try {
      final tRaw = columns[1].trim();
      final tParsed = double.tryParse(tRaw);
      if (tParsed != null) _torque = tParsed;
    } catch (e) {
      // Suprime
    }

    if (fatAD > 0) {
      try {
        torque = _roundTo(_torque / fatAD, 4);
      } catch (e) {
        // Suprime
      }
    }
  }

  // Mantém nome original do C#
  void SetDataFinalResultByColunms(List<String> Colunas, double FatAD) {
    setDataFinalResultByColumns(Colunas, FatAD);
  }

  // --- Helpers de serialização / desserialização ---

  Map<String, dynamic> toMap() {
    return {
      'thresholdDir': thresholdDir,
      'resultDir': resultDir,
      'type': type,
      'torque': torque,
      'angle': angle,
      'sampleTime': sampleTime,
      'date': date.toIso8601String(),
      'batteryLevel': batteryLevel,
    };
  }

  factory DataResult.fromMap(Map<String, dynamic> map) {
    final res = DataResult();
    try {
      if (map.containsKey('thresholdDir')) {
        final v = map['thresholdDir'];
        res.thresholdDir = (v is int) ? v : int.tryParse(v.toString()) ?? res.thresholdDir;
      } else if (map.containsKey('ThresholdDir')) {
        final v = map['ThresholdDir'];
        res.thresholdDir = (v is int) ? v : int.tryParse(v.toString()) ?? res.thresholdDir;
      }

      if (map.containsKey('resultDir')) {
        final v = map['resultDir'];
        res.resultDir = (v is int) ? v : int.tryParse(v.toString()) ?? res.resultDir;
      } else if (map.containsKey('ResultDir')) {
        final v = map['ResultDir'];
        res.resultDir = (v is int) ? v : int.tryParse(v.toString()) ?? res.resultDir;
      }

      res.type = map['type']?.toString() ?? map['Type']?.toString() ?? res.type;

      if (map.containsKey('torque')) {
        final v = map['torque'];
        if (v is double) res.torque = v;
        else if (v is int) res.torque = v.toDouble();
        else res.torque = double.tryParse(v.toString()) ?? res.torque;
      }

      if (map.containsKey('angle')) {
        final v = map['angle'];
        if (v is double) res.angle = v;
        else if (v is int) res.angle = v.toDouble();
        else res.angle = double.tryParse(v.toString()) ?? res.angle;
      }

      if (map.containsKey('sampleTime')) {
        final v = map['sampleTime'];
        res.sampleTime = (v is int) ? v : int.tryParse(v.toString()) ?? res.sampleTime;
      }

      if (map.containsKey('date')) {
        final v = map['date'];
        try {
          res.date = DateTime.parse(v.toString());
        } catch (e) {
          // Suprime e mantém valor padrão
        }
      } else if (map.containsKey('Date')) {
        final v = map['Date'];
        try {
          res.date = DateTime.parse(v.toString());
        } catch (e) {
          // Suprime
        }
      }

      if (map.containsKey('batteryLevel')) {
        final v = map['batteryLevel'];
        if (v is double) res.batteryLevel = v;
        else if (v is int) res.batteryLevel = v.toDouble();
        else res.batteryLevel = double.tryParse(v.toString()) ?? res.batteryLevel;
      } else if (map.containsKey('BatteryLevel')) {
        final v = map['BatteryLevel'];
        if (v is double) res.batteryLevel = v;
        else if (v is int) res.batteryLevel = v.toDouble();
        else res.batteryLevel = double.tryParse(v.toString()) ?? res.batteryLevel;
      }
    } catch (e) {
      // Suprime
    }

    return res;
  }

  String toJson() => json.encode(toMap());

  factory DataResult.fromJson(String source) {
    try {
      final decoded = json.decode(source);
      if (decoded is Map<String, dynamic>) {
        return DataResult.fromMap(decoded);
      }
    } catch (e) {
      // Suprime e retorna objeto padrão
    }
    return DataResult();
  }

  @override
  String toString() {
    return 'DataResult(type: $type, torque: $torque, angle: $angle, batteryLevel: $batteryLevel, date: $date)';
  }
}