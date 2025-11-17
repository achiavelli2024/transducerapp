// Classe convertida de C# -> Dart
// Arquivo: DebugInformation.dart
// Observações:
// - Mantive o comportamento e os nomes das propriedades do C# o mais fiel possível,
//   aplicando apenas a convenção lowerCamelCase para os campos (como no restante do projeto).
// - Tipos: int para inteiros (equivalente a ulong/int do C# no contexto do app Flutter),
//   double para valores em ponto flutuante (TorqueConversionFactor, AngleConversionFactor).
// - Adicionei métodos auxiliares completos (fromMap, toMap, toJson, fromJson, copyWith)
//   para facilitar uso no Flutter e manter o código completo e testável.
// - Tratamento de parsing: uso de tryParse e verificações para suprimir erros (comportamento
//   semelhante ao código C# que não lançava exceções ao popular propriedades).
// - Comentários em português explicando cada campo e método.

import 'dart:convert';

class DebugInformation {
  // Estado geral do transdutor (equivalente a State em C#)
  int state = 0;

  // Código/valor de erro (equivalente a Error em C#)
  int error = 0;

  // Temperatura em milli-Celsius (Temp_mC no C#)
  // Ex.: 25000 == 25.000 °C
  int tempMC = 0;

  // Interface (valor numérico que identifica a interface)
  int interface = 0;

  // Tipo do transdutor/dispositivo
  int type = 0;

  // Fonte de alimentação
  int powerSource = 0;

  // Estado de alimentação (ligado/desligado/erro etc.)
  int powerState = 0;

  // Estado da alimentação analógica
  int analogPowerState = 0;

  // Estado da alimentação do encoder
  int encoderPowerState = 0;

  // Tensão medida em milli-volts (PowerVoltage_mV)
  int powerVoltageMV = 0;

  // Tempo de auto power-off em segundos (AutoPowerOFFSpan_s)
  int autoPowerOFFSpanS = 0;

  // Razão do reset (ResetReason)
  int resetReason = 0;

  // Tempo de atividade em segundos (AliveTime_s)
  int aliveTimeS = 0;

  // Informação de rastreio / string extra (RastInfo)
  String rastInfo = '';

  // Fatores de conversão (Torque e Ângulo)
  double torqueConversionFactor = 0.0;
  double angleConversionFactor = 0.0;

  DebugInformation();

  // Construtor de conveniência com todos os parâmetros opcionais
  DebugInformation.withValues({
    this.state = 0,
    this.error = 0,
    this.tempMC = 0,
    this.interface = 0,
    this.type = 0,
    this.powerSource = 0,
    this.powerState = 0,
    this.analogPowerState = 0,
    this.encoderPowerState = 0,
    this.powerVoltageMV = 0,
    this.autoPowerOFFSpanS = 0,
    this.resetReason = 0,
    this.aliveTimeS = 0,
    this.rastInfo = '',
    this.torqueConversionFactor = 0.0,
    this.angleConversionFactor = 0.0,
  });

  // Criar a partir de um Map (útil ao desserializar JSON ou receber Map do protocolo)
  // O método tenta ler chaves tanto em camelCase quanto em PascalCase e com/sem underscores,
  // para ser compatível com diferentes fontes (por exemplo: dados vindo do C#).
  factory DebugInformation.fromMap(Map<String, dynamic> map) {
    final info = DebugInformation();

    try {
      int _toInt(dynamic v) {
        if (v == null) return 0;
        if (v is int) return v;
        if (v is double) return v.toInt();
        if (v is String) return int.tryParse(v.trim()) ?? 0;
        return 0;
      }

      double _toDouble(dynamic v) {
        if (v == null) return 0.0;
        if (v is double) return v;
        if (v is int) return v.toDouble();
        if (v is String) return double.tryParse(v.trim()) ?? 0.0;
        return 0.0;
      }

      String _toString(dynamic v) {
        if (v == null) return '';
        return v.toString();
      }

      // Helper para obter valor considerando múltiplas variações do nome da chave
      dynamic _getAny(Map<String, dynamic> m, List<String> keys) {
        for (final k in keys) {
          if (m.containsKey(k)) return m[k];
        }
        return null;
      }

      info.state = _toInt(_getAny(map, ['state', 'State']));
      info.error = _toInt(_getAny(map, ['error', 'Error']));
      info.tempMC = _toInt(_getAny(map, ['tempMC', 'Temp_mC', 'TempMC', 'temp_mC']));
      info.interface = _toInt(_getAny(map, ['interface', 'Interface']));
      info.type = _toInt(_getAny(map, ['type', 'Type']));
      info.powerSource = _toInt(_getAny(map, ['powerSource', 'PowerSource']));
      info.powerState = _toInt(_getAny(map, ['powerState', 'PowerState']));
      info.analogPowerState = _toInt(_getAny(map, ['analogPowerState', 'AnalogPowerState']));
      info.encoderPowerState = _toInt(_getAny(map, ['encoderPowerState', 'EncoderPowerState']));
      info.powerVoltageMV = _toInt(_getAny(map, ['powerVoltageMV', 'PowerVoltage_mV', 'PowerVoltageMV']));
      info.autoPowerOFFSpanS = _toInt(_getAny(map, ['autoPowerOFFSpanS', 'AutoPowerOFFSpan_s', 'AutoPowerOFFSpan_s']));
      info.resetReason = _toInt(_getAny(map, ['resetReason', 'ResetReason']));
      info.aliveTimeS = _toInt(_getAny(map, ['aliveTimeS', 'AliveTime_s', 'AliveTime_s']));
      info.rastInfo = _toString(_getAny(map, ['rastInfo', 'RastInfo']));
      info.torqueConversionFactor =
          _toDouble(_getAny(map, ['torqueConversionFactor', 'TorqueConversionFactor']));
      info.angleConversionFactor =
          _toDouble(_getAny(map, ['angleConversionFactor', 'AngleConversionFactor']));
    } catch (e) {
      // Suprime erros de parsing para reproduzir o comportamento do C# original (não lançar)
    }

    return info;
  }

  // Converter para Map (útil para serializar em JSON ou enviar para UI)
  Map<String, dynamic> toMap() {
    return {
      'state': state,
      'error': error,
      'tempMC': tempMC,
      'interface': interface,
      'type': type,
      'powerSource': powerSource,
      'powerState': powerState,
      'analogPowerState': analogPowerState,
      'encoderPowerState': encoderPowerState,
      'powerVoltageMV': powerVoltageMV,
      'autoPowerOFFSpanS': autoPowerOFFSpanS,
      'resetReason': resetReason,
      'aliveTimeS': aliveTimeS,
      'rastInfo': rastInfo,
      'torqueConversionFactor': torqueConversionFactor,
      'angleConversionFactor': angleConversionFactor,
    };
  }

  // Criar a partir de uma string JSON
  factory DebugInformation.fromJson(String source) {
    try {
      final map = json.decode(source);
      if (map is Map<String, dynamic>) {
        return DebugInformation.fromMap(map);
      }
    } catch (e) {
      // Suprime erro e retorna objeto padrão
    }
    return DebugInformation();
  }

  // Serializar para JSON
  String toJson() => json.encode(toMap());

  // Método de cópia para facilitar atualizações imutáveis
  DebugInformation copyWith({
    int? state,
    int? error,
    int? tempMC,
    int? interface,
    int? type,
    int? powerSource,
    int? powerState,
    int? analogPowerState,
    int? encoderPowerState,
    int? powerVoltageMV,
    int? autoPowerOFFSpanS,
    int? resetReason,
    int? aliveTimeS,
    String? rastInfo,
    double? torqueConversionFactor,
    double? angleConversionFactor,
  }) {
    return DebugInformation.withValues(
      state: state ?? this.state,
      error: error ?? this.error,
      tempMC: tempMC ?? this.tempMC,
      interface: interface ?? this.interface,
      type: type ?? this.type,
      powerSource: powerSource ?? this.powerSource,
      powerState: powerState ?? this.powerState,
      analogPowerState: analogPowerState ?? this.analogPowerState,
      encoderPowerState: encoderPowerState ?? this.encoderPowerState,
      powerVoltageMV: powerVoltageMV ?? this.powerVoltageMV,
      autoPowerOFFSpanS: autoPowerOFFSpanS ?? this.autoPowerOFFSpanS,
      resetReason: resetReason ?? this.resetReason,
      aliveTimeS: aliveTimeS ?? this.aliveTimeS,
      rastInfo: rastInfo ?? this.rastInfo,
      torqueConversionFactor: torqueConversionFactor ?? this.torqueConversionFactor,
      angleConversionFactor: angleConversionFactor ?? this.angleConversionFactor,
    );
  }

  @override
  String toString() {
    return 'DebugInformation(state: $state, error: $error, tempMC: $tempMC, interface: $interface, '
        'type: $type, powerSource: $powerSource, powerState: $powerState, analogPowerState: $analogPowerState, '
        'encoderPowerState: $encoderPowerState, powerVoltageMV: $powerVoltageMV, autoPowerOFFSpanS: $autoPowerOFFSpanS, '
        'resetReason: $resetReason, aliveTimeS: $aliveTimeS, rastInfo: $rastInfo, '
        'torqueConversionFactor: $torqueConversionFactor, angleConversionFactor: $angleConversionFactor)';
  }
}