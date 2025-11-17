// Arquivo: ITransducer.dart
// Conversão de C# -> Dart da interface ITransducers.ITransducer
// Observações:
// - Tipos C# foram mapeados para equivalentes Dart (decimal -> double, ushort -> int, ulong -> int).
// - Eventos (delegates + event) foram convertidos em typedefs para callbacks e métodos para
//   adicionar/remover listeners (como interface, não implementamos a gestão de listeners aqui).
// - GetMeasures do C# (com muitos out params) foi convertido para um tipo de retorno estruturado
//   (Measures) para manter o mesmo comportamento sem usar parâmetros out (incompatíveis com Dart).
// - Todos os métodos são declarados em lowerCamelCase seguindo convenções Dart, mantendo
//   nomes similares aos originais para facilitar a leitura e manutenção.
// - Método dispose() substitui IDisposable.Dispose() do C#.

import 'dart:async';
import '../models/data_information.dart';
import '../models/dataResult.dart';
import '../models/DebugInformation.dart';
import '../models/CountersInformation.dart';


/// Tipos de callback (equivalente aos delegates do C#)
typedef DataInformationReceiver = void Function(DataInformation data);
typedef DataResultReceiver = void Function(DataResult data);
typedef DataTesteResultReceiver = void Function(List<DataResult> testeResult);
typedef ErrorReceiver = void Function(int err);
typedef DebugInformationReceiver = void Function(DebugInformation data);
typedef EventReceiver = void Function(TransducerEvent ev);
typedef CountersInformationReceiver = void Function(CountersInformation data);

/// Enums convertidos do C#
enum TesteType { torqueOnly, torqueAngle, angleCheck }

enum ToolType {
  toolType1,
  toolType2,
  toolType3,
  toolType4,
  toolType5,
  toolType6,
  toolType7,
  toolType8,
  toolType9,
  toolType10
}

enum TransducerEvent { calibrationOK, oldTransducerFirmwareDetected }

enum EDirection { cw, ccw, both }

enum EPCSpeed { slow, medium, fast }

enum ECharPoints { veryFew, few, medium, many }

/// Resultado estruturado para substituir o uso de out params do C# GetMeasures.
/// Mantém todos os campos que eram retornados por out parameters no C#.
class Measures {
  bool success;
  int ptim;
  int pok;
  int perr;
  int pgarb;
  int iansavg;
  bool validBatteryInfo;
  int batteryLevel;
  bool charging;
  int interfaceIndex;
  int lastStateTimeout;
  int lastStateErr;

  Measures({
    this.success = false,
    this.ptim = 0,
    this.pok = 0,
    this.perr = 0,
    this.pgarb = 0,
    this.iansavg = 0,
    this.validBatteryInfo = false,
    this.batteryLevel = 0,
    this.charging = false,
    this.interfaceIndex = 0,
    this.lastStateTimeout = 0,
    this.lastStateErr = 0,
  });

  @override
  String toString() {
    return 'Measures(success: $success, ptim: $ptim, pok: $pok, perr: $perr, pgarb: $pgarb, '
        'iansavg: $iansavg, validBatteryInfo: $validBatteryInfo, batteryLevel: $batteryLevel, '
        'charging: $charging, interfaceIndex: $interfaceIndex, lastStateTimeout: $lastStateTimeout, '
        'lastStateErr: $lastStateErr)';
  }
}

/// NOTE: As classes abaixo (DataInformation, DataResult, DebugInformation, CountersInformation)
/// devem existir no projeto (foram convertidas em arquivos separados conforme solicitado).
/// Aqui referenciamos apenas os nomes delas — não as reimplementamos neste arquivo.

/// Interface/contrato do Transducer (equivalente à interface ITransducer do C#).
/// Implementadores devem prover comportamento equivalente ao projeto C# original.
abstract class ITransducer {
  // --- Propriedades (setters/getters) ---
  set portName(String name);
  set portIndex(int index);

  bool get isConnected;

  set ethIp(String ip);
  set ethPort(int port);

  // --- Eventos ---
  // Observação: em Dart não existe "event" nativo como em C#. Aqui definimos métodos
  // que o implementador deverá providenciar para adicionar/remover listeners.
  // Isso mantém a possibilidade de múltiplos inscritos (sem limitar a apenas um callback).

  // DataInformation
  void addDataInformationListener(DataInformationReceiver listener);
  void removeDataInformationListener(DataInformationReceiver listener);

  // DataResult
  void addDataResultListener(DataResultReceiver listener);
  void removeDataResultListener(DataResultReceiver listener);

  // TesteResult (lista de DataResult)
  void addTesteResultListener(DataTesteResultReceiver listener);
  void removeTesteResultListener(DataTesteResultReceiver listener);

  // Erros
  void addErrorListener(ErrorReceiver listener);
  void removeErrorListener(ErrorReceiver listener);

  // DebugInformation
  void addDebugInformationListener(DebugInformationReceiver listener);
  void removeDebugInformationListener(DebugInformationReceiver listener);

  // Eventos gerais do transdutor
  void addEventListener(EventReceiver listener);
  void removeEventListener(EventReceiver listener);

  // CountersInformation
  void addCountersInformationListener(CountersInformationReceiver listener);
  void removeCountersInformationListener(CountersInformationReceiver listener);

  // --- Operações principais (métodos do C# convertidos) ---
  void requestInformation();
  void writeSetup(DataInformation info);

  /// Calibração: valores em double (equivalente ao decimal do C#)
  void calibrate(double appliedTorque, double currentTorque, double appliedAngle, double currentAngle);

  // Sobrecargas SetTestParameter convertidas para assinaturas com parâmetros opcionais/necessários.
  // Em Dart não existe overload; portanto diferentes métodos ou parâmetros opcionais são usados.
  void setTestParameter(DataInformation info, TesteType type, ToolType toolType, double nominalTorque, double threshold);

  void setTestParameterAdvanced(
      DataInformation info,
      TesteType type,
      ToolType toolType,
      double nominalTorque,
      double threshold,
      double thresholdEnd,
      int timeoutEndMs,
      int timeStepMs,
      int filterFrequency,
      EDirection direction,
      );

  void setTestParameterFull(
      DataInformation info,
      TesteType type,
      ToolType toolType,
      double nominalTorque,
      double threshold,
      double thresholdEnd,
      int timeoutEndMs,
      int timeStepMs,
      int filterFrequency,
      EDirection direction,
      double torqueTarget,
      double torqueMin,
      double torqueMax,
      double angleTarget,
      double angleMin,
      double angleMax,
      int delayToDetectFirstPeakMs,
      int timeToIgnoreNewPeakAfterFinalThresholdMs,
      );

  // Click wrench / pulse parameters (ushort in C# -> int here)
  void setTestParameterClickWrench(int fallPercentage, int risePercentage, int minTimeBetweenPulsesMs);

  // Serviços e controle
  void startService();
  void stopService();
  void startCalibration();
  void startReadData();
  void stopReadData();
  void setZeroTorque();
  void setZeroAngle();
  void startCommunication();

  void setTorqueOffset(double torqueOffset);

  // Lista de testes (opcional)
  void setTests(List<String>? s);

  // Keep-alive / ack
  void ka();

  // Performance / speed / charpoints
  void setPerformance(EPCSpeed pcSpeed, ECharPoints charPoints);

  /// Get measures: retorna um objeto Measures contendo todos os valores que antes eram out parameters.
  Measures getMeasures();

  // Dispose (equivalente a IDisposable)
  void dispose();
}