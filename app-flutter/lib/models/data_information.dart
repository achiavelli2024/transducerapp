// lib/models/data_information.dart
// Versão Dart da classe C# DataInformation (DataInformation.cs)
// - Campos espelhados do C#
// - Método setDataInformationByColumns(List<String> cols) que replica SetDataInformationByColunms do C#
// - Parsing tolerante (tratamento de erros, substituição de vírgula por ponto para doubles)
// - Comentários e instruções de uso

class DataInformation {
  // Campos correspondentes ao C# DataInformation
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

  // Construtor vazio com defaults (igual ao comportamento do C# quando valores faltam)
  DataInformation();

  // Fábrica a partir de colunas (mesma lógica do C# SetDataInformationByColunms)
  // Colunas: array de strings onde índices específicos contém os valores
  // Observação: o array C# começa com Colunas[0]; o C# usa índices como 1,2,3,... igual aqui.
  void setDataInformationByColumns(List<String> cols) {
    try {
      // Segurança: garantir tamanho mínimo antes de acessar posições
      // 1 -> KeyName
      if (cols.length > 1) {
        keyName = cols[1].trim();
      } else {
        keyName = '';
      }

      // 2 -> TorqueLimit (int)
      if (cols.length > 2) {
        torqueLimit = _tryParseInt(cols[2], fallback: 0);
      } else {
        torqueLimit = 0;
      }

      // 3 -> FullScale (int)
      if (cols.length > 3) {
        fullScale = _tryParseInt(cols[3], fallback: 0);
      } else {
        fullScale = 0;
      }

      // 6 -> DeviceType (string)
      if (cols.length > 6) {
        deviceType = cols[6].trim();
      } else {
        deviceType = '';
      }

      // 9 -> PowerType (int) (opcional)
      if (cols.length > 9) {
        powerType = _tryParseInt(cols[9], fallback: 0);
      } else {
        powerType = 0;
      }

      // 10 -> AutoPowerOff (int) (opcional)
      if (cols.length > 10) {
        autoPowerOff = _tryParseInt(cols[10], fallback: 0);
      } else {
        autoPowerOff = 0;
      }

      // 11 -> CommunicationType (int) (opcional)
      if (cols.length > 11) {
        communicationType = _tryParseInt(cols[11], fallback: 0);
      } else {
        communicationType = 0;
      }

      // Se existirem índices 12..16 -> conversões e strings (torque/angle conv, model, hw, fw, hardid)
      if (cols.length > 12) {
        // 12 -> TorqueConversionFactor (double)
        torqueConversionFactor = _tryParseDouble(cols[12], fallback: 1.0);

        // 13 -> AngleConversionFactor (double)
        angleConversionFactor = _tryParseDouble(cols[13], fallback: 1.0);

        // 14 -> Model
        if (cols.length > 14) model = cols[14].trim();
        // 15 -> HW
        if (cols.length > 15) hw = cols[15].trim();
        // 16 -> FW
        if (cols.length > 16) fw = cols[16].trim();
        // 17 -> HardID (opcional); se ausente, fallback para KeyName
        if (cols.length > 17) {
          hardID = cols[17].trim();
        } else {
          hardID = keyName;
        }
      } else {
        // Defaults caso faltem essas colunas (segue a lógica do C#)
        torqueConversionFactor = 1.0;
        angleConversionFactor = 1.0;
        model = '';
        hw = '';
        fw = '';
        hardID = keyName;
      }
    } catch (e) {
      // Em caso de erro não-crítico, log (caller pode logar) e manter defaults/valores já atribuídos.
      // Não lançamos exceção para não quebrar parsing de pacotes parcialmente corretos.
      //print('DataInformation.setDataInformationByColumns parse error: $e');
    }
  }

  // Helper: tentativas de parse seguro
  int _tryParseInt(String s, {int fallback = 0}) {
    try {
      return int.parse(s.trim());
    } catch (_) {
      // tenta remover textos não numéricos comuns (ex.: espaços, trailing chars)
      final cleaned = s.replaceAll(RegExp(r'[^0-9\-]'), '');
      try {
        return int.parse(cleaned);
      } catch (_) {
        return fallback;
      }
    }
  }

  double _tryParseDouble(String s, {double fallback = 1.0}) {
    try {
      // aceitar vírgula como separador decimal (pt-BR), substituir por ponto
      final normalized = s.trim().replaceAll(',', '.');
      return double.parse(normalized);
    } catch (_) {
      // tenta extrair números e ponto
      final cleaned = s.replaceAll(RegExp(r'[^0-9\-\.,]'), '').replaceAll(',', '.');
      try {
        return double.parse(cleaned);
      } catch (_) {
        return fallback;
      }
    }
  }

  @override
  String toString() {
    return 'DataInformation{keyName: $keyName, torqueLimit: $torqueLimit, fullScale: $fullScale, '
        'powerType: $powerType, autoPowerOff: $autoPowerOff, torqueConversionFactor: $torqueConversionFactor, '
        'angleConversionFactor: $angleConversionFactor, model: $model, hw: $hw, fw: $fw, hardID: $hardID, '
        'deviceType: $deviceType, communicationType: $communicationType}';
  }
}