// Arquivo: DataInformation.dart
// Conversão direta de C# -> Dart da classe ITransducers.DataInformation
//
// Observações importantes:
// - Mantive os nomes das propriedades do C# em lowerCamelCase para seguir convenções Dart,
//   mas preservei um método com o mesmo nome original SetDataInformationByColunms caso
//   exista código que dependa desse nome.
// - Tipos: int para inteiros (TorqueLimit, FullScale, PowerType, AutoPowerOff, CommunicationType),
//   double para fatores de conversão (TorqueConversionFactor, AngleConversionFactor).
// - O método SetDataInformationByColunms do C# suprimia exceções — aqui também suprimimos
//   exceções (try/catch vazio) para manter exatamente o mesmo comportamento:
//   atribuições realizadas antes de uma exceção permanecem.
// - Implementei helpers (fromMap, toMap, fromJson, toJson, copyWith) para facilitar uso no Flutter.
// - Incluí comentários em português e tratamento robusto de parsing (int.tryParse/double.tryParse)
//   mas mantendo suprimir exceções como no original.

import 'dart:convert';

class DataInformation {
  // Propriedades correspondentes ao C#
  String keyName = '';
  int torqueLimit = 0;
  int fullScale = 0;
  int powerType = 0;
  int autoPowerOff = 0;

  double torqueConversionFactor = 1.0;
  double angleConversionFactor = 1.0;

  String model = '';
  String hw = '';
  String fw = '';
  String hardID = '';

  String deviceType = '';

  int communicationType = 0;

  DataInformation();

  // Construtor de conveniência com parâmetros nomeados
  DataInformation.withValues({
    this.keyName = '',
    this.torqueLimit = 0,
    this.fullScale = 0,
    this.powerType = 0,
    this.autoPowerOff = 0,
    this.torqueConversionFactor = 1.0,
    this.angleConversionFactor = 1.0,
    this.model = '',
    this.hw = '',
    this.fw = '',
    this.hardID = '',
    this.deviceType = '',
    this.communicationType = 0,
  });

  // Método equivalente ao SetDataInformationByColunms do C#
  // Recebe um array/lista de colunas (List<String>) e popula as propriedades conforme o código original.
  // Suprime exceções para manter o mesmo comportamento.
  void setDataInformationByColumns(List<String> columns) {
    try {
      // Conforme o código C# original, KeyName é Colunas[1]
      if (columns.length > 1) {
        keyName = columns[1].trim();
      } else {
        keyName = '';
      }

      if (columns.length > 2) {
        torqueLimit = int.parse(columns[2].trim());
      }

      if (columns.length > 3) {
        fullScale = int.parse(columns[3].trim());
      }

      if (columns.length > 6) {
        deviceType = columns[6].trim();
      }

      if (columns.length > 9) {
        powerType = int.parse(columns[9].TrimmedOrEmpty());
      }

      if (columns.length > 10) {
        autoPowerOff = int.parse(columns[10].TrimmedOrEmpty());
      }

      if (columns.length > 11) {
        communicationType = int.parse(columns[11].TrimmedOrEmpty());
      }

      if (columns.length > 12) {
        // Colunas[12] -> TorqueConversionFactor
        torqueConversionFactor = double.parse(columns[12].trim());
        // Colunas[13] -> AngleConversionFactor
        angleConversionFactor = double.parse(columns[13].trim());
        // Colunas[14] -> Model
        model = (columns.length > 14) ? columns[14].trim() : '';
        // Colunas[15] -> HW
        hw = (columns.length > 15) ? columns[15].trim() : '';
        // Colunas[16] -> FW
        fw = (columns.length > 16) ? columns[16].trim() : '';
        // Colunas[17] -> HardID (opcional)
        if (columns.length > 17) {
          hardID = columns[17].trim();
        } else {
          hardID = keyName;
        }
      } else {
        // Valores padrão conforme o C# original
        torqueConversionFactor = 1;
        angleConversionFactor = 1;
        model = '';
        hw = '';
        fw = '';
        hardID = keyName;
      }
    } catch (e) {
      // Suprime quaisquer erros como no código C# original.
      // Em caso de erro, as atribuições realizadas antes da exceção permanecem.
    }
  }

  // Mantém o nome original do método (mesma grafia do C#) caso exista código dependente.
  void SetDataInformationByColunms(List<String> Colunas) {
    setDataInformationByColumns(Colunas);
  }

  // --- Helpers de serialização / desserialização ---

  Map<String, dynamic> toMap() {
    return {
      'keyName': keyName,
      'torqueLimit': torqueLimit,
      'fullScale': fullScale,
      'powerType': powerType,
      'autoPowerOff': autoPowerOff,
      'torqueConversionFactor': torqueConversionFactor,
      'angleConversionFactor': angleConversionFactor,
      'model': model,
      'hw': hw,
      'fw': fw,
      'hardID': hardID,
      'deviceType': deviceType,
      'communicationType': communicationType,
    };
  }

  factory DataInformation.fromMap(Map<String, dynamic> map) {
    final info = DataInformation();
    try {
      dynamic _get(Map<String, dynamic> m, List<String> keys) {
        for (final k in keys) {
          if (m.containsKey(k)) return m[k];
        }
        return null;
      }

      String _asString(dynamic v) {
        if (v == null) return '';
        return v.toString();
      }

      int _asInt(dynamic v) {
        if (v == null) return 0;
        if (v is int) return v;
        if (v is double) return v.toInt();
        final s = v.toString().trim();
        return int.tryParse(s) ?? 0;
      }

      double _asDouble(dynamic v) {
        if (v == null) return 1.0;
        if (v is double) return v;
        if (v is int) return v.toDouble();
        final s = v.toString().trim();
        return double.tryParse(s) ?? 1.0;
      }

      info.keyName = _asString(_get(map, ['keyName', 'KeyName']));
      info.torqueLimit = _asInt(_get(map, ['torqueLimit', 'TorqueLimit']));
      info.fullScale = _asInt(_get(map, ['fullScale', 'FullScale']));
      info.powerType = _asInt(_get(map, ['powerType', 'PowerType']));
      info.autoPowerOff = _asInt(_get(map, ['autoPowerOff', 'AutoPowerOff']));
      info.torqueConversionFactor = _asDouble(_get(map, ['torqueConversionFactor', 'TorqueConversionFactor']));
      info.angleConversionFactor = _asDouble(_get(map, ['angleConversionFactor', 'AngleConversionFactor']));
      info.model = _asString(_get(map, ['model', 'Model']));
      info.hw = _asString(_get(map, ['hw', 'HW']));
      info.fw = _asString(_get(map, ['fw', 'FW']));
      info.hardID = _asString(_get(map, ['hardID', 'HardID']));
      if (info.hardID.isEmpty) info.hardID = info.keyName;
      info.deviceType = _asString(_get(map, ['deviceType', 'DeviceType']));
      info.communicationType = _asInt(_get(map, ['communicationType', 'CommunicationType']));
    } catch (e) {
      // Suprimir erros para manter comportamento igual ao original
    }
    return info;
  }

  String toJson() => json.encode(toMap());

  factory DataInformation.fromJson(String source) {
    try {
      final decoded = json.decode(source);
      if (decoded is Map<String, dynamic>) {
        return DataInformation.fromMap(decoded);
      }
    } catch (e) {
      // Suprime erro e retorna objeto padrão
    }
    return DataInformation();
  }

  // Método de cópia (útil para atualizações imutáveis)
  DataInformation copyWith({
    String? keyName,
    int? torqueLimit,
    int? fullScale,
    int? powerType,
    int? autoPowerOff,
    double? torqueConversionFactor,
    double? angleConversionFactor,
    String? model,
    String? hw,
    String? fw,
    String? hardID,
    String? deviceType,
    int? communicationType,
  }) {
    return DataInformation.withValues(
      keyName: keyName ?? this.keyName,
      torqueLimit: torqueLimit ?? this.torqueLimit,
      fullScale: fullScale ?? this.fullScale,
      powerType: powerType ?? this.powerType,
      autoPowerOff: autoPowerOff ?? this.autoPowerOff,
      torqueConversionFactor: torqueConversionFactor ?? this.torqueConversionFactor,
      angleConversionFactor: angleConversionFactor ?? this.angleConversionFactor,
      model: model ?? this.model,
      hw: hw ?? this.hw,
      fw: fw ?? this.fw,
      hardID: hardID ?? this.hardID,
      deviceType: deviceType ?? this.deviceType,
      communicationType: communicationType ?? this.communicationType,
    );
  }

  @override
  String toString() {
    return 'DataInformation(keyName: $keyName, torqueLimit: $torqueLimit, fullScale: $fullScale, '
        'deviceType: $deviceType, powerType: $powerType, autoPowerOff: $autoPowerOff, communicationType: $communicationType, '
        'torqueConversionFactor: $torqueConversionFactor, angleConversionFactor: $angleConversionFactor, '
        'model: $model, hw: $hw, fw: $fw, hardID: $hardID)';
  }
}

// Extensão auxiliar local: TrimmedOrEmpty para evitar repetição.
// Usada acima para parse de índices opcionais. (simula comportamento seguro)
extension _StringExt on String {
  String TrimmedOrEmpty() {
    return this.trim();
  }
}