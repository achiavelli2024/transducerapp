// PhoenixTransducer - V16.2.1 (corrigido e completo) - modificado para throttling de TQ
// Este arquivo foi adaptado a partir do seu V16.2.1 fornecido.
// Mantive a lógica do dispatcher, CRC byte-based, parser GD e tratamento de fragmentos.
// Comentários foram adicionados para aprendizado.
// IMPORTANTE: Este arquivo depende de ../models/data_information.dart e transducer_logger.dart no projeto.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/data_information.dart';
import 'transducer_logger.dart';

// ------------------- Enums / Classes públicas (compatíveis com C#) -------------------
enum TesteType {
  TorqueOnly, // 0
  TorqueAngle, // 1
  AngleCheck // 2
}

// ToolType no C# começa em 1..10 (valores explícitos).
enum ToolType {
  ToolType1,
  ToolType2,
  ToolType3,
  ToolType4,
  ToolType5,
  ToolType6,
  ToolType7,
  ToolType8,
  ToolType9,
  ToolType10,
}

enum TransducerEvent {
  CalibrationOK,
  OldTransducerFirmwareDetected,
}

enum eDirection {
  CW,
  CCW,
  BOTH,
}

enum ePCSpeed { Slow, Medium, Fast }

enum eCharPoints { VeryFew, Few, Medium, Many }

enum eAquisitionState { Idle, Threshold, Timeout, Finished }

class DataResult {
  double Torque = 0.0;
  double Angle = 0.0;
  int SampleTime = 0;
  String Type = '';
  int ThresholdDir = 0;
  int ResultDir = 0;
}

// Interface equivalente ao ITransducer.cs do C#
abstract class ITransducer {
  // Eventos / Callbacks
  void Function(String event)? onEvent;
  void Function(TransducerEvent ev)? onTransducerEvent;
  void Function(int errCode)? onError;

  // Callbacks específicos
  void Function(DataInformation di)? onDataInformation;
  void Function(DataResult dr)? onDataResult;
  void Function(List<DataResult> results)? onTesteResult;
  void Function(DebugInformation debug)? onDebugInformation;
  void Function(CountersInformation counters)? onCountersInformation;

  Future<void> startService(String ip, int port);
  Future<void> stopService();
  Future<void> startCommunication();
  void requestInformation();
  void startReadData();
  void stopReadData();
  void setZeroTorque();
  void setZeroAngle();
  void setTorqueOffset(double offset);
  Future<void> setTestParameter(DataInformation? info, TesteType type, ToolType toolType, double nominalTorque, double threshold, { double thresholdEnd = 0, int timeoutEndMs = 1, int timeStepMs = 1, int filterFrequency = 500, eDirection direction = eDirection.CW, double torqueTarget = 0, double torqueMin = 0, double torqueMax = 0, double angleTarget = 0, double angleMin = 0, double angleMax = 0, int delayToDetectFirstPeakMs = 0, int timeToIgnoreNewPeakAfterFinalThresholdMs = 0 });
  Future<bool> initRead({int ackTimeoutMs = 500});
  Future<void> dispose();
}

// DataInformation (definição local compatível com C# - você já tem ../models/data_information.dart)
class CountersInformation {
  String cycles = '0';
  String overshuts = '0';
  String higherOvershut = '0';
  String additional1 = '0';
  String additional2 = '0';
}

class DebugInformation {
  int State = 0;
  int Error = 0;
  int Temp_mC = 0;
  int Interface = 0;
  int PowerSource = 0;
  int PowerState = 0;
  int AnalogPowerState = 0;
  int EncoderPowerState = 0;
  int PowerVoltage_mV = 0;
  int AutoPowerOFFSpan_s = 0;
  int ResetReason = 0;
  int AliveTime_s = 0;
  double TorqueConversionFactor = 1.0;
  double AngleConversionFactor = 1.0;
  String RastInfo = '';
}

// ------------------- Internal state enum -------------------
enum enumEState {
  eIdle,
  eMustSendGetID,
  eWaitingID,
  eMustSendReadCommand,
  eWaitingAnswerReadCommand,
  eWaitBetweenReads,
  eMustSendRequestInformation,
  eWaitAnswerRequestInformation,
  eMustSendAquisitionConfig,
  eWaitingAquisitionConfig,
  eMustSendGetStatus,
  eWaitingGetStatus,
  eMustSendGetChartBlock,
  eWaitingChartBlock,
  eMustSendZeroTorque,
  eWaitingZeroTorque,
  eMustSendZeroAngle,
  eWaitingZeroAngle,
  eMustConfigure,
  eWaitingConfigure,
  eMustGetDeviceStatus,
  eWaitingDeviceStatus,
  eMustSendCalibrate,
  eWaitingCalibrate,
  eMustSendGetCounters,
  eWaitingCounters,
  eMustSendAquisitionClickWrenchConfig,
  eWaitingAquisitionClickWrenchConfig,
  eMustSendAquisitionAdditionalConfig,
  eWaitingAquisitionAdditionalConfig,
  eMustSendAquisitionAdditional2Config,
  eWaitingAquisitionAdditional2Config,
  eMustSendTorqueOffset,
  eWaitingTorqueOffset
}

// ------------------- PhoenixTransducer -------------------
class PhoenixTransducer {
  // Callbacks/events
  void Function(String event)? onEvent; // textual/backwards-compatible
  void Function(TransducerEvent ev)? onTransducerEvent; // typed event (C#-like)
  void Function(int errCode)? onError;
  void Function(DataInformation di)? onDataInformation;
  void Function(DataResult dr)? onDataResult;
  void Function(List<DataResult> results)? onTesteResult;
  void Function(DebugInformation debug)? onDebugInformation;
  void Function(CountersInformation counters)? onCountersInformation;

  // Configuration (mirror C# logic)
  int DEF_SLOW_TIMER_INTERVAL = 40;
  static const int DEF_FAST_TIMER_INTERVAL = 1;

  static const int DEF_TIMESPAN_TIMEOUT_ID = 500;
  static const int DEF_TIMESPAN_TIMEOUT_READ = 400;

  // INTERESSANTE: se o Flutter estiver enviando comandos mais rápido que o C#, ajuste este valor
  // para aumentar o tempo mínimo entre leituras (em ms). Valor default: 100 (mantido do original),
  // porém é possível configurar via setReadPollingIntervalMs().
  int DEF_TIMESPAN_BETWEENREADS = 1000; // intervalo padrão entre leituras (ms)
  int DEF_TIMESPAN_BETWEENREADS_TRACING = 100;

  static const int DEF_TIMESPAN_TIMEOUT_REQUESTINFORMATION = 500;
  static const int DEF_TIMESPAN_ABORTGARBAGE = 300;
  static const int DEF_TIMESPAN_AQUISITIONCONFIG = 200;
  static const int DEF_TIMESPAN_GETSTATUS = 1200;
  static const int DEF_TIMESPAN_WAITCHARTBLOCK = 500;
  static const int DEF_TIMESPAN_TIMEOUT_ZERO = 300;
  static const int DEF_TIMESPAN_TIMEOUT_CONFIGURATION = 500;
  static const int DEF_TIMESPAN_GETDEVICESTATUS = 1200;
  static const int DEF_TIMESPAN_TIMEOUT_DEVICESTATUS = 400;
  static const int DEF_TIMESPAN_TIMEOUT_CALIBRATE = 400;
  static const int DEF_TIMESPAN_TIMEOUT_COUNTERS = 300;

  static const int DEF_MAX_ERRS = 60;
  static const bool DEF_IGNOREGRAPHCRC = true;

  int DEF_MAX_GRAPHSIZE = 1200;
  int DEF_MAX_BLOCKSIZE = 240;

  enumEState _state = enumEState.eIdle;

  String _ip = '';
  int _port = 23;
  Socket? _socket;
  bool _isConnected = false;

  Timer? _dispatcherTimer;

  // Flags (mirror do C#)
  bool mustSendGetID = false;
  bool mustSendRequestInformation = false;
  bool mustSendReadData = false; // enable TQ polling
  bool mustSendAquisitionConfig = false; // SA
  bool mustSendGetStatus = false;
  bool mustSendGetChartBlock = false;
  bool captureNewTightening = false;
  bool mustSendZeroTorque = false;
  bool mustSendZeroAngle = false;
  bool mustConfigure = false;
  bool newConfiguration = false;
  bool mustCalibrate = false;
  bool mustSendGetCounters = false;

  String configuration = '';
  int bufferSize = 0;
  int tickDeviceStatus = 0;

  bool mustSendTorqueOffset = false;
  bool mustSendAquisitionClickWrenchConfig = false; // CS
  bool mustSendAquisitionAdditionalConfig = false; // SB
  bool mustSendAquisitionAdditional2Config = false; // SC
  double torqueOffset = 0.0;

  // Avoid flags: when set, dispatcher will not attempt to send that packet (useful for old firmware)
  bool avoidSendTorqueOffset = false;
  bool avoidSendAquisitionClickWrenchConfig = false;
  bool avoidSendAquisitionAdditionalConfig = false;
  bool avoidSendAquisitionAdditional2Config = false;

  String _id = '000000000000';
  bool waitAns = false;
  int _awaitedSize = 0;
  List<int> _rxBuffer = <int>[];

  double torqueConversionFactor = 1.0;
  double angleConversionFactor = 1.0;

  // acquisition config mirror (SA) + SB/SC fields
  ToolType acquisitionToolType = ToolType.ToolType1;
  double acquisitionThreshold = 0;
  double acquisitionThresholdEnd = 0;
  int acquisitionTimeoutEnd_ms = 1;
  int acquisitionTimeStep_ms = 1;
  int acquisitionFilterFrequency = 500;
  eDirection acquisitionDir = eDirection.CW;

  // SB (additional) parameters
  double acquisitionNominalTorque = 0; // NominalTorque
  double acquisitionTorqueTarget = 0;
  double acquisitionTorqueMin = 0;
  double acquisitionTorqueMax = 0;
  double acquisitionAngleTarget = 0;
  double acquisitionAngleMin = 0;
  double acquisitionAngleMax = 0;
  int acquisitionDelayToDetectFirstPeak_ms = 0;
  int acquisitionTimeToIgnoreNewPeakAfterFinalThreshold_ms = 0;

  TesteType acquisitionTestType = TesteType.TorqueOnly; // TesteType

  int clickFall = 1;
  int clickRise = 1;
  int clickMinTime_ms = 3;

  List<DataResult> _testeResultsList = [];

  int iConsecErrs = 0;
  int iConsecTimeoutOrInvalid = 0;
  int iConsecErrsUnknown = 0;
  int iTrashing = 0;

  int tickTxCommand = 0;
  int tickRxCommand = 0;

  // suppression window after sending ZO to avoid polling conflicts
  int _suppressUntil = 0;

  // handshake / start-read request
  bool startReadRequested = false;
  Timer? _enableReadTimer;

  // sync for initRead
  bool _inSyncOperation = false;
  final Map<String, Completer<bool>> _ackCompleters = {};

  // reconnect helpers
  bool _userInitiatedStop = false; // if true, do not attempt reconnect when socket closes
  int _reconnectAttempts = 0;
  final int _maxReconnectAttempts = 5;
  final int _baseReconnectDelayMs = 500; // base delay for backoff

  // calibrate fields
  double calibrate_appliedTorque = 0.0;
  double calibrate_currentTorque = 0.0;
  double calibrate_appliedAngle = 0.0;
  double calibrate_currentAngle = 0.0;

  // NEW: port index configurável (antes sempre retornava 0)
  int _portIndexField = 0;
  void setPortIndex(int idx) {
    _portIndexField = idx;
    TransducerLogger.logFmt('PortIndex set to {0}', [idx]);
    if (onEvent != null) onEvent!('PortIndex set to $idx');
  }
  int getPortIndex() => _portIndexField;

  // NEW: enable dummy injection behavior (workaround used in C#).
  bool enableDummyInjection = false;
  int countSimulateGoodChartBlocksBeforeFail = 3;
  bool simulateChartBlockFail = false;

  PhoenixTransducer({String initialId = '000000000000'}) {
    _id = initialId;
    // inicializa _lastTQSendMs com valor negativo para enviar imediatamente quando habilitado
    _lastTQSendMs = -999999999;
    // define leitura polling interval como o valor default (você pode ajustar via setter)
    _readPollingIntervalMs = DEF_TIMESPAN_BETWEENREADS;
  }

  void setDeviceId(String deviceId12) {
    if (deviceId12.length == 12) {
      _id = deviceId12;
      TransducerLogger.logFmt('Device ID set manually to {0}', [_id]);
      if (onEvent != null) onEvent!('Device ID set to $_id');
    } else {
      TransducerLogger.logFmt('setDeviceId: provided id length != 12: {0}', [deviceId12]);
      if (onEvent != null) onEvent!('setDeviceId: invalid length');
    }
  }

  // ----------------------------
  // Public API
  // ----------------------------
  Future<void> startService(String ip, int port) async {
    _ip = ip;
    _port = port;
    _userInitiatedStop = false;
    TransducerLogger.logFmt('startService requested: {0}:{1}', [ip, port]);
    if (onEvent != null) onEvent!('startService $ip:$port');
    await _internalStartServiceEth();
    _startDispatcherTimer();
  }

  Future<void> stopService() async {
    TransducerLogger.log('stopService called');
    if (onEvent != null) onEvent!('stopService');
    _userInitiatedStop = true;
    await _internalStopService();
  }

  Future<void> startCommunication() async {
    mustSendGetID = true;
    mustSendGetCounters = true;
    TransducerLogger.log('startCommunication: MustSendGetID & MustSendGetCounters set');
    if (onEvent != null) onEvent!('startCommunication');
  }

  void requestInformation() {
    mustSendRequestInformation = true;
    TransducerLogger.log('requestInformation: MustSendRequestInformation set');
    if (onEvent != null) onEvent!('requestInformation');
  }

  void startReadData() {
    captureNewTightening = true;
    TransducerLogger.log('startReadData called: startReadRequested = true (waiting SA/CS ACKs)');
    startReadRequested = true;
    if (onEvent != null) onEvent!('startReadData requested');
  }

  void stopReadData() {
    mustSendReadData = false;
    mustSendAquisitionConfig = false;
    mustSendGetChartBlock = false;
    captureNewTightening = false;
    mustSendAquisitionClickWrenchConfig = false;
    mustSendAquisitionAdditionalConfig = false;
    mustSendAquisitionAdditional2Config = false;
    startReadRequested = false;
    _enableReadTimer?.cancel();
    _enableReadTimer = null;
    TransducerLogger.log('stopReadData called: acquisition flags cleared');
    if (onEvent != null) onEvent!('stopReadData');
  }

  void setZeroTorque() {
    mustSendZeroTorque = true;
    final now = DateTime.now().millisecondsSinceEpoch;
    _suppressUntil = now + 300;
    TransducerLogger.logFmt('setZeroTorque called - suppression until {0}', [_suppressUntil]);
    if (onEvent != null) onEvent!('setZeroTorque called');
  }

  void setZeroAngle() {
    mustSendZeroAngle = true;
    final now = DateTime.now().millisecondsSinceEpoch;
    _suppressUntil = now + 300;
    TransducerLogger.logFmt('setZeroAngle called - suppression until {0}', [_suppressUntil]);
    if (onEvent != null) onEvent!('setZeroAngle called');
  }

  void setTorqueOffset(double offset) {
    mustSendTorqueOffset = true;
    torqueOffset = offset;
    TransducerLogger.logFmt('setTorqueOffset: {0}', [offset]);
    if (onEvent != null) onEvent!('setTorqueOffset $offset');
  }

  // KA helper (replica comportamento de KA() do C#)
  void _KA() {
    tickDeviceStatus = DateTime.now().millisecondsSinceEpoch;
    TransducerLogger.log('KA() invoked - tickDeviceStatus updated');
    if (onEvent != null) onEvent!('KA invoked');
  }

  Future<void> setTestParameter(
      DataInformation? info,
      TesteType type,
      ToolType toolType,
      double nominalTorque,
      double threshold, {
        double thresholdEnd = 0,
        int timeoutEndMs = 1,
        int timeStepMs = 1,
        int filterFrequency = 500,
        eDirection direction = eDirection.CW,
        double torqueTarget = 0,
        double torqueMin = 0,
        double torqueMax = 0,
        double angleTarget = 0,
        double angleMin = 0,
        double angleMax = 0,
        int delayToDetectFirstPeakMs = 0,
        int timeToIgnoreNewPeakAfterFinalThresholdMs = 0,
      }) async {
    _KA();

    acquisitionToolType = toolType;
    acquisitionThreshold = threshold;
    acquisitionThresholdEnd = thresholdEnd;
    acquisitionTimeoutEnd_ms = timeoutEndMs;
    acquisitionTimeStep_ms = timeStepMs;
    acquisitionFilterFrequency = filterFrequency;
    acquisitionDir = direction;

    acquisitionTestType = type;
    acquisitionNominalTorque = nominalTorque;

    acquisitionTorqueTarget = torqueTarget;
    acquisitionTorqueMin = torqueMin;
    acquisitionTorqueMax = torqueMax;
    acquisitionAngleTarget = angleTarget;
    acquisitionAngleMin = angleMin;
    acquisitionAngleMax = angleMax;
    acquisitionDelayToDetectFirstPeak_ms = delayToDetectFirstPeakMs;
    acquisitionTimeToIgnoreNewPeakAfterFinalThreshold_ms = timeToIgnoreNewPeakAfterFinalThresholdMs;

    mustSendAquisitionConfig = true;
    mustSendAquisitionAdditionalConfig = true;
    mustSendAquisitionAdditional2Config = true;

    if (info != null) {
      TransducerLogger.log('setTestParameter received DataInformation (not required to build SA/SB here)');
    }

    try {
      TransducerLogger.logFmt(
        'setTestParameter stored: TesteType={0} NominalTorque={1} Threshold={2} ThresholdEnd={3} timeoutEndMs={4} timeStepMs={5} filterFreq={6} dir={7} tool={8} torqueTarget={9} torqueMin={10} torqueMax={11} angleTarget={12} angleMin={13} angleMax={14} delayFirstPeakMs={15} ignoreNewPeakMs={16}',
        [
          type.toString(),
          nominalTorque,
          threshold,
          thresholdEnd,
          timeoutEndMs,
          timeStepMs,
          filterFrequency,
          direction.toString(),
          (toolType.index + 1),
          torqueTarget,
          torqueMin,
          torqueMax,
          angleTarget,
          angleMin,
          angleMax,
          delayToDetectFirstPeakMs,
          timeToIgnoreNewPeakAfterFinalThresholdMs
        ],
      );
    } catch (e, st) {
      TransducerLogger.logException(e, 'setTestParameter logFmt');
      TransducerLogger.log('stack: $st');
    }
  }

  Future<void> setTestParameterShort(
      DataInformation? info,
      TesteType type,
      ToolType toolType,
      double nominalTorque,
      double threshold,
      ) {
    return setTestParameter(
      info,
      type,
      toolType,
      nominalTorque,
      threshold,
      thresholdEnd: threshold / 2.0,
      timeoutEndMs: 10,
      timeStepMs: 1,
      filterFrequency: 500,
      direction: eDirection.CW,
      torqueTarget: 0,
      torqueMin: 0,
      torqueMax: 0,
      angleTarget: 0,
      angleMin: 0,
      angleMax: 0,
      delayToDetectFirstPeakMs: 0,
      timeToIgnoreNewPeakAfterFinalThresholdMs: 0,
    );
  }

  void setTestParameter_ClickWrench(int fallPercentage, int risePercentage, int minTimeBetweenPulsesMs) {
    clickFall = fallPercentage;
    clickRise = risePercentage;
    clickMinTime_ms = minTimeBetweenPulsesMs;
    mustSendAquisitionClickWrenchConfig = true;
    TransducerLogger.logFmt('setTestParameter_ClickWrench stored fall={0} rise={1} minMs={2}', [fallPercentage, risePercentage, minTimeBetweenPulsesMs]);
    if (onEvent != null) onEvent!('CS stored fall=$fallPercentage rise=$risePercentage minMs=$minTimeBetweenPulsesMs');
  }

  void setTestParameterClickWrench(int fallPercentage, int risePercentage, int minTimeBetweenPulsesMs) {
    try {
      setTestParameter_ClickWrench(fallPercentage, risePercentage, minTimeBetweenPulsesMs);
    } catch (e, st) {
      TransducerLogger.logException(e, 'setTestParameterClickWrench wrapper');
    }
  }

  void _maybeEnableReadAfterConfigAck() {
    try {
      if (startReadRequested &&
          !mustSendAquisitionConfig &&
          !mustSendAquisitionClickWrenchConfig &&
          !mustSendAquisitionAdditionalConfig &&
          !mustSendAquisitionAdditional2Config) {
        if (_enableReadTimer == null) {
          TransducerLogger.log('All acquisition config ACKs seen (or avoided) -> scheduling mustSendReadData enable in 50ms');
          _enableReadTimer = Timer(const Duration(milliseconds: 50), () {
            mustSendReadData = true;
            startReadRequested = false;
            _enableReadTimer = null;
            TransducerLogger.log('mustSendReadData enabled after short delay (via _maybeEnableReadAfterConfigAck)');
            if (onEvent != null) onEvent!('mustSendReadData enabled');
          });
        }
      }
    } catch (e) {
      TransducerLogger.logException(e, '_maybeEnableReadAfterConfigAck');
    }
  }

  Future<bool> initRead({int ackTimeoutMs = 500}) async {
    if (!_isConnected) {
      TransducerLogger.log('initRead: not connected');
      return false;
    }

    TransducerLogger.log('InitRead: START (synchronous sequence)');
    _inSyncOperation = true;

    try {
      TransducerLogger.log('InitRead: SetZeroTorque');
      String ztCmd = _id + 'ZO' + '1' + '0';
      bool okZT = await _sendAndWaitAck(ztCmd, 'ZO', timeoutMs: ackTimeoutMs);
      TransducerLogger.logFmt('InitRead: SetZeroTorque ack -> {0}', [okZT]);
      await Future.delayed(const Duration(milliseconds: 10));

      TransducerLogger.log('InitRead: SetZeroAngle');
      String zaCmd = _id + 'ZO0' + '1';
      bool okZA = await _sendAndWaitAck(zaCmd, 'ZO', timeoutMs: ackTimeoutMs);
      TransducerLogger.logFmt('InitRead: SetZeroAngle ack -> {0}', [okZA]);
      await Future.delayed(const Duration(milliseconds: 10));

      TransducerLogger.logFmt('InitRead: SetTestParameter_ClickWrench({0},{1},{2})', [clickFall, clickRise, clickMinTime_ms]);
      String csCmd = _id + 'CS' + _limitToHex2(clickFall) + _limitToHex2(clickRise) + _limitToHex2(clickMinTime_ms);
      bool okCS = await _sendAndWaitAck(csCmd, 'CS', timeoutMs: ackTimeoutMs);
      TransducerLogger.logFmt('InitRead: CS ack -> {0}', [okCS]);

      TransducerLogger.log('InitRead: SetTestParameter (full) -> SA');
      String sSA = _id +
          'SA' +
          _limitToHex8(_thresholdToAd(acquisitionThreshold)) +
          _limitToHex8(_thresholdToAd(acquisitionThresholdEnd)) +
          _limitToHex4(acquisitionTimeoutEnd_ms) +
          _limitToHex4(acquisitionTimeStep_ms) +
          _limitToHex4(acquisitionFilterFrequency) +
          _limitToHex2(acquisitionDir.index) +
          _limitToHex2((acquisitionToolType.index + 1)); // ToolType in C# starts at 1
      bool okSA = await _sendAndWaitAck(sSA, 'SA', timeoutMs: ackTimeoutMs);
      TransducerLogger.logFmt('InitRead: SA ack -> {0}', [okSA]);

      // Wait 100ms as in C#
      await Future.delayed(const Duration(milliseconds: 100));

      TransducerLogger.log('InitRead: calling StartReadData');
      startReadData();
      TransducerLogger.log('InitRead: StartReadData called');

      bool overall = okZT && okZA && okCS && okSA;
      TransducerLogger.logFmt('InitRead: finished overall={0}', [overall]);
      return overall;
    } finally {
      _inSyncOperation = false;
    }
  }

  // ----------------------------
  // Internal TCP (only TCP)
  Future<void> _internalStartServiceEth() async {
    try {
      if (_socket != null) {
        try {
          await _socket!.close();
        } catch (_) {}
        _socket = null;
      }
      TransducerLogger.logFmt('Connecting to {0}:{1}', [_ip, _port]);
      _socket = await Socket.connect(_ip, _port, timeout: const Duration(seconds: 5));
      _isConnected = true;
      _reconnectAttempts = 0;
      TransducerLogger.log('Socket connected');
      _socket!.listen(_onData, onDone: _onDone, onError: _onSocketError, cancelOnError: false);
      tickDeviceStatus = DateTime.now().millisecondsSinceEpoch;
      if (onEvent != null) onEvent!('socket_connected');
    } catch (ex) {
      _isConnected = false;
      TransducerLogger.logException(ex, '_internalStartServiceEth');
      if (onError != null) onError!(101);
      if (!_userInitiatedStop) {
        _scheduleReconnect();
      }
    }
  }

  Future<void> _internalStopService() async {
    try {
      TransducerLogger.log('Internal stop service - closing socket');
      _userInitiatedStop = true;
      try {
        await _socket?.close();
      } catch (ex) {
        TransducerLogger.logException(ex, '_internalStopService close socket');
      }
    } catch (ex) {
      TransducerLogger.logException(ex, '_internalStopService');
    } finally {
      _socket = null;
      _isConnected = false;
      _stopDispatcherTimer();
      TransducerLogger.log('Internal stop service completed');
      if (onEvent != null) onEvent!('socket_closed');
    }
  }

  void _onDone() {
    _isConnected = false;
    TransducerLogger.log('Socket onDone - connection closed by remote');
    if (onEvent != null) onEvent!('socket_done');
    if (onError != null) onError!(103);
    if (!_userInitiatedStop) {
      TransducerLogger.log('Socket closed by remote; scheduling reconnect attempts.');
      _scheduleReconnect();
    }
  }

  void _onSocketError(Object err) {
    _isConnected = false;
    TransducerLogger.logException(err, '_onSocketError');
    if (onError != null) onError!(102);
    if (!_userInitiatedStop) {
      TransducerLogger.log('_onSocketError: scheduling reconnect attempts (not user-initiated)');
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      TransducerLogger.logFmt('Max reconnect attempts ({0}) reached - will not try further', [_maxReconnectAttempts]);
      return;
    }
    _reconnectAttempts++;
    final delayMs = _baseReconnectDelayMs * (1 << (_reconnectAttempts - 1));
    final cappedDelay = delayMs > 10000 ? 10000 : delayMs;
    TransducerLogger.logFmt('Scheduling reconnect attempt {0} in {1}ms', [_reconnectAttempts, cappedDelay]);
    Timer(Duration(milliseconds: cappedDelay), () async {
      if (_userInitiatedStop) {
        TransducerLogger.log('User requested stop while waiting to reconnect; aborting reconnect attempt');
        return;
      }
      TransducerLogger.logFmt('Reconnect attempt {0} now (to {1}:{2})', [_reconnectAttempts, _ip, _port]);
      try {
        await _internalStartServiceEth();
        if (_isConnected) {
          TransducerLogger.log('Reconnect successful');
          if (_dispatcherTimer == null) _startDispatcherTimer();
        } else {
          TransducerLogger.log('Reconnect attempt did not succeed (socket not connected)');
          _scheduleReconnect();
        }
      } catch (e) {
        TransducerLogger.logException(e, 'reconnect attempt error');
        _scheduleReconnect();
      }
    });
  }

  // ----------------------------
  // Dispatcher (state machine)
  void _startDispatcherTimer() {
    _stopDispatcherTimer();
    _dispatcherTimer = Timer.periodic(Duration(milliseconds: DEF_SLOW_TIMER_INTERVAL), (t) {
      _dispatcherTick();
    });
    TransducerLogger.log('Dispatcher timer started interval=${DEF_SLOW_TIMER_INTERVAL}ms');
  }

  void _stopDispatcherTimer() {
    try {
      _dispatcherTimer?.cancel();
    } catch (_) {}
    _dispatcherTimer = null;
    TransducerLogger.log('Dispatcher timer stopped');
  }

  // -------------- NEW: Throttling/Configurable polling --------------
  // _readPollingIntervalMs: tempo mínimo entre envios de TQ (ms).
  // Por padrão, herdamos DEF_TIMESPAN_BETWEENREADS, mas você pode ajustar runtime com setReadPollingIntervalMs.
  int _readPollingIntervalMs = 100;
  int _lastTQSendMs = 0; // timestamp (ms) do último envio TQ

  /// Ajusta intervalo mínimo entre leituras TQ (ms).
  /// Use este método para calibrar a cadência para o comportamento observado no C#.
  void setReadPollingIntervalMs(int ms) {
    if (ms <= 0) return;
    _readPollingIntervalMs = ms;
    TransducerLogger.logFmt('Read polling interval set to {0} ms', [ms]);
    if (onEvent != null) onEvent!('Read polling interval set to $ms ms');
  }

  // Para leitura inicial/semente
  // (já inicializado no construtor)

  // ----------------------------
  void _dispatcherTick() {
    try {
      if (!_isConnected) return;
      if (_inSyncOperation) return;

      final now = DateTime.now().millisecondsSinceEpoch;

      // suppression window after ZO: only allow high-priority actions
      if (_suppressUntil > now) {
        TransducerLogger.logFmt('Dispatcher: suppression active, ms left={0}', [_suppressUntil - now]);
        if (mustSendZeroTorque) {
          if (_state != enumEState.eWaitingZeroTorque) _state = enumEState.eMustSendZeroTorque;
        } else if (mustSendZeroAngle) {
          if (_state != enumEState.eWaitingZeroAngle) _state = enumEState.eMustSendZeroAngle;
        } else if (mustConfigure && configuration.isNotEmpty) {
          if (_state != enumEState.eWaitingConfigure) _state = enumEState.eMustConfigure;
        } else if (mustSendTorqueOffset && !avoidSendTorqueOffset) {
          if (_state != enumEState.eWaitingTorqueOffset) _state = enumEState.eMustSendTorqueOffset;
        } else if (mustCalibrate) {
          if (_state != enumEState.eWaitingCalibrate) _state = enumEState.eMustSendCalibrate;
        } else if (mustSendRequestInformation) {
          if (_state != enumEState.eWaitAnswerRequestInformation) _state = enumEState.eMustSendRequestInformation;
        } else {
          return; // remain suppressed
        }
      }

      // If startReadRequested is set, only allow mustSendReadData when all acquisition config flags are cleared
      if (startReadRequested &&
          !mustSendAquisitionConfig &&
          !mustSendAquisitionClickWrenchConfig &&
          !mustSendAquisitionAdditionalConfig &&
          !mustSendAquisitionAdditional2Config) {
        if (_enableReadTimer == null) {
          TransducerLogger.log('All acquisition config ACKs seen -> scheduling mustSendReadData enable in 50ms');
          _enableReadTimer = Timer(const Duration(milliseconds: 50), () {
            mustSendReadData = true;
            startReadRequested = false;
            _enableReadTimer = null;
            TransducerLogger.log('mustSendReadData enabled after short delay');
          });
        }
      }

      // decision tree (prioritize flags)
      if (mustSendGetID || (_id == '000000000000')) {
        if (_state != enumEState.eWaitingID) _state = enumEState.eMustSendGetID;
      } else if (mustConfigure) {
        if (configuration.isNotEmpty) {
          if (_state != enumEState.eWaitingConfigure) _state = enumEState.eMustConfigure;
        } else {
          mustConfigure = false;
        }
      } else if (mustSendZeroTorque) {
        if (_state != enumEState.eWaitingZeroTorque) _state = enumEState.eMustSendZeroTorque;
      } else if (mustSendZeroAngle) {
        if (_state != enumEState.eWaitingZeroAngle) _state = enumEState.eMustSendZeroAngle;
      } else if (mustSendTorqueOffset) {
        if (avoidSendTorqueOffset) mustSendTorqueOffset = false;
        else if (_state != enumEState.eWaitingTorqueOffset) _state = enumEState.eMustSendTorqueOffset;
      } else if (mustCalibrate) {
        if (_state != enumEState.eWaitingCalibrate) _state = enumEState.eMustSendCalibrate;
      } else if (mustSendRequestInformation) {
        if (_state != enumEState.eWaitAnswerRequestInformation) _state = enumEState.eMustSendRequestInformation;
      } else if (mustSendGetChartBlock) {
        if (_state != enumEState.eWaitingChartBlock) _state = enumEState.eMustSendGetChartBlock;
      } else if (mustSendAquisitionConfig) {
        if (_state != enumEState.eWaitingAquisitionConfig) _state = enumEState.eMustSendAquisitionConfig;
      } else if (mustSendAquisitionClickWrenchConfig) {
        if (avoidSendAquisitionClickWrenchConfig) mustSendAquisitionClickWrenchConfig = false;
        else if (_state != enumEState.eWaitingAquisitionClickWrenchConfig) _state = enumEState.eMustSendAquisitionClickWrenchConfig;
      } else if (mustSendAquisitionAdditionalConfig) {
        if (avoidSendAquisitionAdditionalConfig) mustSendAquisitionAdditionalConfig = false;
        else if (_state != enumEState.eWaitingAquisitionAdditionalConfig) _state = enumEState.eMustSendAquisitionAdditionalConfig;
      } else if (mustSendAquisitionAdditional2Config) {
        if (avoidSendAquisitionAdditional2Config) mustSendAquisitionAdditional2Config = false;
        else if (_state != enumEState.eWaitingAquisitionAdditional2Config) _state = enumEState.eMustSendAquisitionAdditional2Config;
      } else if (mustSendReadData) {
        // Aqui é onde aplicamos o throttle explícito para TQ:
        // - Só permitimos enviar TQ se:
        //   1) não estivermos esperando resposta TQ anterior (_state != eWaitingAnswerReadCommand)
        //   2) ou, se estivermos entre leituras, o tempo desde a última resposta Rx (tickRxCommand)
        //      for maior que DEF_TIMESPAN_BETWEENREADS (comportamento legado)
        //   3) e adicionalmente o tempo desde o último envio TQ (último TX) deve ser >= _readPollingIntervalMs
        //
        // Esta verificação garante que o polling em Flutter não fique "mais rápido" do que o observado no C#.
        if (_state != enumEState.eWaitingAnswerReadCommand) {
          final int sinceLastTx = now - _lastTQSendMs;
          final int sinceLastRx = now - tickRxCommand;
          // verifica as duas condições (mantém a condição legacy com tickRxCommand e adiciona throttling por TX)
          if ((_state != enumEState.eWaitBetweenReads || sinceLastRx >= DEF_TIMESPAN_BETWEENREADS) &&
              sinceLastTx >= _readPollingIntervalMs) {
            _state = enumEState.eMustSendReadCommand;
          } else {
            // não enviar ainda, aguardar próximo tick
            // opcional: log trace para debugging (comentar se poluir logs)
            // TransducerLogger.logFmt('Read throttle: sinceLastRx={0} sinceLastTx={1} minPoll={2}', [sinceLastRx, sinceLastTx, _readPollingIntervalMs]);
          }
        }
      } else if (mustSendGetStatus) {
        if (_state != enumEState.eWaitingGetStatus) _state = enumEState.eMustSendGetStatus;
      } else if (_state != enumEState.eWaitingAnswerReadCommand &&
          (DateTime.now().millisecondsSinceEpoch - tickDeviceStatus > DEF_TIMESPAN_GETSTATUS)) {
        if (_state != enumEState.eWaitingDeviceStatus) _state = enumEState.eMustGetDeviceStatus;
      } else {
        _state = enumEState.eIdle;
      }

      // SEND actions
      switch (_state) {
        case enumEState.eMustSendGetID:
          _state = enumEState.eWaitingID;
          _sendCommand(_padHex(_portIndexToHex(getPortIndex()), 2) + '0000000000ID');
          break;
        case enumEState.eMustSendReadCommand:
          {
            // Antes de enviar, atualizamos _lastTQSendMs para controlar o throttle
            _lastTQSendMs = DateTime.now().millisecondsSinceEpoch;
            _state = enumEState.eWaitingAnswerReadCommand;
            final String payload = _id + 'TQ';
            TransducerLogger.logFmt('Dispatching SendCommand payload (ascii): {0}', [payload]);
            try {
              final List<int> bytes = latin1.encode(payload);
              TransducerLogger.logFmt('Dispatching SendCommand payload hex: {0}', [_toHex(bytes)]);
            } catch (e) {
              TransducerLogger.logException(e, 'Dispatching SendCommand payload hex encode');
            }

            tickTxCommand = DateTime.now().millisecondsSinceEpoch;
            _sendCommand(payload);
            TransducerLogger.logFmt('TQ requested (tickTxCommand={0})', [tickTxCommand]);
          }
          break;
        case enumEState.eMustSendRequestInformation:
          _state = enumEState.eWaitAnswerRequestInformation;
          _sendCommand(_id + 'DI');
          break;
        case enumEState.eMustSendGetStatus:
          _state = enumEState.eWaitingGetStatus;
          _sendCommand(_id + 'LS');
          break;
        case enumEState.eMustGetDeviceStatus:
          _state = enumEState.eWaitingDeviceStatus;
          _sendCommand(_id + 'DS');
          break;
        case enumEState.eMustSendZeroTorque:
          _state = enumEState.eWaitingZeroTorque;
          String zt = mustSendZeroTorque ? '1' : '0';
          _sendCommand(_id + 'ZO' + zt + '0');
          break;
        case enumEState.eMustSendZeroAngle:
          _state = enumEState.eWaitingZeroAngle;
          String za = mustSendZeroAngle ? '1' : '0';
          _sendCommand(_id + 'ZO0' + za);
          break;
        case enumEState.eMustSendTorqueOffset:
          _state = enumEState.eWaitingTorqueOffset;
          int ad = _nmToAd(torqueOffset);
          _sendCommand(_id + 'SO' + ad.toRadixString(16).padLeft(8, '0').toUpperCase());
          break;
        case enumEState.eMustSendCalibrate:
          _state = enumEState.eWaitingCalibrate;
          double ft = (calibrate_appliedTorque != 0 && calibrate_currentTorque != 0)
              ? (calibrate_appliedTorque / calibrate_currentTorque)
              : 1.0;
          double fa = (calibrate_appliedAngle != 0 && calibrate_currentAngle != 0)
              ? (calibrate_appliedAngle / calibrate_currentAngle)
              : 1.0;
          int cwTorque = ((torqueConversionFactor * ft) / 0.000000000001).toInt();
          int cwAngle = ((angleConversionFactor * fa) / 0.001).toInt();
          String sCW = _id +
              'CW' +
              cwTorque.toRadixString(16).padLeft(8, '0').toUpperCase() +
              cwAngle.toRadixString(16).padLeft(8, '0').toUpperCase() +
              '00000000' +
              '00000000' +
              '00000000';
          _sendCommand(sCW);
          break;
        case enumEState.eMustSendAquisitionConfig:
          _state = enumEState.eWaitingAquisitionConfig;
          String sSA = _id +
              'SA' +
              _limitToHex8(_thresholdToAd(acquisitionThreshold)) +
              _limitToHex8(_thresholdToAd(acquisitionThresholdEnd)) +
              _limitToHex4(acquisitionTimeoutEnd_ms) +
              _limitToHex4(acquisitionTimeStep_ms) +
              _limitToHex4(acquisitionFilterFrequency) +
              _limitToHex2(acquisitionDir.index) +
              _limitToHex2((acquisitionToolType.index + 1)); // ToolType starts at 1 in C#

          TransducerLogger.logFmt('Built SA (pre-CRC): {0}', [sSA]);
          TransducerLogger.logFmt('Built SA payload hex (pre-CRC): {0}', [_toHex(latin1.encode(sSA))]);

          _sendCommand(sSA);

          break;
        case enumEState.eMustSendAquisitionClickWrenchConfig:
          _state = enumEState.eWaitingAquisitionClickWrenchConfig;
          String sCS = _id +
              'CS' +
              _limitToHex2(clickFall) +
              _limitToHex2(clickRise) +
              _limitToHex2(clickMinTime_ms);

          TransducerLogger.logFmt('Built CS (pre-CRC): {0}', [sCS]);
          TransducerLogger.logFmt('Built CS payload hex (pre-CRC): {0}', [_toHex(latin1.encode(sCS))]);

          _sendCommand(sCS);

          break;
        case enumEState.eMustSendAquisitionAdditionalConfig:
          _state = enumEState.eWaitingAquisitionAdditionalConfig;
          String sSB = _id +
              'SB' +
              _limitToHex8(_nmToAd(acquisitionTorqueTarget)) +
              _limitToHex8(_nmToAd(acquisitionTorqueMax)) +
              _limitToHex8(_nmToAd(acquisitionTorqueMin)) +
              _limitToHex8(_convertAngleToBus(acquisitionAngleTarget)) +
              _limitToHex8(_convertAngleToBus(acquisitionAngleMax)) +
              _limitToHex8(_convertAngleToBus(acquisitionAngleMin)) +
              '00000000';
          TransducerLogger.logFmt('Sending SB with Nominal={0} Target={1} Min={2} Max={3} AngleTarget={4}', [
            acquisitionNominalTorque,
            acquisitionTorqueTarget,
            acquisitionTorqueMin,
            acquisitionTorqueMax,
            acquisitionAngleTarget
          ]);

          TransducerLogger.logFmt('Built SB (pre-CRC): {0}', [sSB]);
          TransducerLogger.logFmt('Built SB payload hex (pre-CRC): {0}', [_toHex(latin1.encode(sSB))]);

          _sendCommand(sSB);

          break;
        case enumEState.eMustSendAquisitionAdditional2Config:
          _state = enumEState.eWaitingAquisitionAdditional2Config;
          String sSC = _id +
              'SC' +
              _limitToHex4(acquisitionDelayToDetectFirstPeak_ms) +
              _limitToHex4(acquisitionTimeToIgnoreNewPeakAfterFinalThreshold_ms) +
              '000000000000000000000000000000000000000000000000';

          TransducerLogger.logFmt('Built SC (pre-CRC): {0}', [sSC]);
          TransducerLogger.logFmt('Built SC payload hex (pre-CRC): {0}', [_toHex(latin1.encode(sSC))]);

          _sendCommand(sSC);

          break;
        case enumEState.eMustSendGetCounters:
          _state = enumEState.eWaitingCounters;
          _sendCommand(_id + 'RC');
          break;
        case enumEState.eMustSendGetChartBlock:
          _state = enumEState.eWaitingChartBlock;
          String sGD = _id +
              'GD' +
              '000100' + // fallback placeholder (should be replaced when actual block info is known)
              '00' +
              '00';
          String cmdToSend = sGD;
          if (configuration.isNotEmpty && configuration.startsWith(_id + 'GD')) {
            cmdToSend = configuration; // allow external config to carry exact GD command
          }
          _sendCommand(cmdToSend);
          break;
        default:
          break;
      }
    } catch (e) {
      TransducerLogger.logException(e, '_dispatcherTick');
      if (onError != null) onError!(999);
    }
  }

  // ----------------------------
  // TX
  // NOTE: send frames as bytes using latin1 (1:1) and CRC computed over bytes.
  void _sendCommand(String cmd, {int awaitedSize = 0}) {
    if (!_isConnected || _socket == null) {
      TransducerLogger.log('SendCommand: not connected');
      if (onError != null) onError!(105);
      return;
    }
    try {
      // Robust GD detection: find 'GD' anywhere in the command and parse the size field
      try {
        if (awaitedSize == 0) {
          final int gdPos = cmd.indexOf('GD');
          if (gdPos >= 0) {
            final String after = (gdPos + 2 < cmd.length) ? cmd.substring(gdPos + 2) : '';
            String sizeHex = '';
            try {
              final RegExp reg = RegExp(r'^([0-9A-Fa-f]{6})([0-9A-Fa-f]{2})');
              final m = reg.firstMatch(after);
              if (m != null && m.groupCount >= 2) {
                sizeHex = m.group(2)!;
              } else if (after.length >= 8) {
                sizeHex = after.substring(6, 8);
              } else if (after.length >= 4) {
                sizeHex = after.substring(4, 6);
              }
            } catch (e) {
              sizeHex = '';
            }

            if (sizeHex.isNotEmpty) {
              try {
                final int blockSize = int.parse(sizeHex, radix: 16);
                final int computed = 18 + blockSize * 5; // same formula used in C#
                awaitedSize = computed;
                TransducerLogger.logFmt('Auto-detected GD at pos {0} blockSize={1} -> awaitedSize={2} (sizeHex={3})', [gdPos, blockSize, awaitedSize, sizeHex]);
              } catch (e) {
                TransducerLogger.logFmt('GD autodetect: could not parse sizeHex "{0}" from cmd after GD: "{1}"', [sizeHex, after]);
              }
            } else {
              TransducerLogger.logFmt('GD autodetect: GD found but couldn\'t extract blockSize from "{0}"', [after]);
            }
          }
        }
      } catch (e) {
        TransducerLogger.logException(e, '_sendCommand GD autodetect');
      }

      // Build payload bytes (latin1)
      final payloadBytes = latin1.encode(cmd);
      // CRC computed over bytes
      final crcStr = _makeCRCFromBytes(payloadBytes); // returns 2-char string (ASCII)
      // Build frame bytes: '[' + payloadBytes + crcAscii + ']'
      final builder = BytesBuilder();
      builder.addByte(0x5B); // '['
      builder.add(payloadBytes);
      builder.add(latin1.encode(crcStr)); // 2-byte ASCII CRC
      builder.addByte(0x5D); // ']'
      final frameBytes = builder.toBytes();

      // Store awaited size (used by parser to assemble fragmented frames)
      _awaitedSize = awaitedSize;
      waitAns = true;
      tickTxCommand = DateTime.now().millisecondsSinceEpoch;

      // Log frame as ascii (latin1) for human-readable logging
      String frameAscii;
      try {
        frameAscii = latin1.decode(frameBytes, allowInvalid: true);
      } catch (_) {
        frameAscii = String.fromCharCodes(frameBytes);
      }
      TransducerLogger.logTx('FRAME', frameAscii);
      TransducerLogger.logFmt('TX FRAME hex: {0}', [_toHex(frameBytes)]);
      TransducerLogger.logFmt('TX awaitedSize: {0}', [awaitedSize]);

      // Send bytes directly
      _socket!.add(frameBytes);
      try {
        _socket!.flush();
      } catch (_) {}
    } catch (e) {
      TransducerLogger.logException(e, '_sendCommand');
      if (onError != null) onError!(106);
    }
  }//_sendCommand

  // ----------------------------
  // sendAndWait ack used by initRead
  Future<bool> _sendAndWaitAck(String cmd, String expectedCom, {int timeoutMs = 500}) async {
    if (!_isConnected || _socket == null) {
      TransducerLogger.log('_sendAndWaitAck: not connected');
      return false;
    }

    final c = Completer<bool>();
    _ackCompleters[expectedCom] = c;
    _inSyncOperation = true;

    try {
      TransducerLogger.logFmt('_sendAndWaitAck: sending cmd={0} waiting for {1} (timeout {2}ms)', [cmd, expectedCom, timeoutMs]);
      _sendCommand(cmd);
      try {
        final bool res = await c.future.timeout(Duration(milliseconds: timeoutMs));
        TransducerLogger.logFmt('_sendAndWaitAck: ack {0} received for {1}', [res, expectedCom]);
        return res;
      } on TimeoutException {
        TransducerLogger.logFmt('_sendAndWaitAck: timeout waiting for {0}', [expectedCom]);
        if (!c.isCompleted) c.complete(false);
        return false;
      }
    } catch (e) {
      TransducerLogger.logException(e, '_sendAndWaitAck');
      if (!c.isCompleted) c.complete(false);
      return false;
    } finally {
      _ackCompleters.remove(expectedCom);
      _inSyncOperation = false;
    }
  }

  // ----------------------------
  // RX parsing (robusto; preserva comportamento C#)
  void _onData(Uint8List data) {
    try {
      TransducerLogger.logRxBytes('socket RAW chunk', data, 0, data.length);
    } catch (_) {}

    _rxBuffer.addAll(data);

    while (true) {
      if (_rxBuffer.isEmpty) return;

      int bspini = _indexOf(_rxBuffer, 0x5B);
      if (bspini < 0) {
        _rxBuffer.clear();
        iTrashing++;
        TransducerLogger.log('No start bracket found - cleared rxBuffer and incremented iTrashing');
        if (onEvent != null) onEvent!('No start bracket - buffer cleared');
        return;
      }
      if (bspini > 0) {
        _rxBuffer.removeRange(0, bspini);
        bspini = 0;
      }

      int bspend = _indexOf(_rxBuffer, 0x5D, start: bspini + 1);
      if (bspend < 0) {
        if (_awaitedSize > 0 && _rxBuffer.length >= _awaitedSize) {
          bspend = _awaitedSize - 1;
          TransducerLogger.logFmt('No \']\' found but _awaitedSize reached -> treating index {0} as end', [bspend]);
        } else {
          return;
        }
      }

      int framedLen = bspend - bspini + 1;
      if (framedLen < 5) {
        _rxBuffer.removeRange(0, bspend + 1);
        TransducerLogger.log('Dropped too-short frame');
        continue;
      }

      List<int> framedBytes = _rxBuffer.sublist(bspini, bspend + 1);

      int payloadEndExclusive = bspend - 2;
      if (payloadEndExclusive <= bspini + 1) {
        _rxBuffer.removeRange(0, bspend + 1);
        TransducerLogger.log('Invalid frame layout, removed segment');
        continue;
      }
      List<int> payloadBytes = _rxBuffer.sublist(bspini + 1, payloadEndExclusive);

      String payloadStr;
      try {
        payloadStr = latin1.decode(payloadBytes, allowInvalid: true);
      } catch (_) {
        payloadStr = String.fromCharCodes(payloadBytes);
      }

      String crcRecv;
      try {
        crcRecv = latin1.decode(_rxBuffer.sublist(bspend - 2, bspend), allowInvalid: true);
      } catch (_) {
        crcRecv = String.fromCharCodes(_rxBuffer.sublist(bspend - 2, bspend));
      }

      String crcCalc;
      try {
        crcCalc = _makeCRCFromBytes(payloadBytes);
      } catch (e) {
        crcCalc = '';
        TransducerLogger.logException(e, '_onData _makeCRCFromBytes');
      }

      String com = '';
      try {
        if (framedBytes.length > 14) {
          com = latin1.decode(framedBytes.sublist(13, 15), allowInvalid: true);
        }
      } catch (_) {
        try {
          if (framedBytes.length > 14) com = String.fromCharCodes(framedBytes.sublist(13, 15));
        } catch (_) {
          com = '';
        }
      }

      bool validCmd = false;
      if (crcCalc == crcRecv) {
        validCmd = true;
      } else {
        if (com == 'GD' && DEF_IGNOREGRAPHCRC) {
          TransducerLogger.logFmt('Accepting GD with CRC mismatch because DEF_IGNOREGRAPHCRC=true (calc={0} recv={1})', [crcCalc, crcRecv]);
          validCmd = true;
        } else {
          validCmd = false;
        }
      }

      if (!validCmd) {
        TransducerLogger.logFmt('Invalid CRC: calc={0} recv={1} (awaitedSize={2}) - dropping framed area', [crcCalc, crcRecv, _awaitedSize]);
        if (_rxBuffer.length > bspend + 1) {
          _rxBuffer.removeRange(0, bspend + 1);
          iConsecErrs++;
          continue;
        } else {
          return;
        }
      }

      String framedAscii;
      try {
        framedAscii = latin1.decode(framedBytes, allowInvalid: true);
      } catch (_) {
        framedAscii = String.fromCharCodes(framedBytes);
      }

      TransducerLogger.logFmt('PARSER framed ascii: {0}', [framedAscii]);
      TransducerLogger.logFmt('PARSER payload hex (start): {0}', [_toHex(payloadBytes.length > 48 ? payloadBytes.sublist(0, 48) : payloadBytes)]);

      _rxBuffer.removeRange(0, bspend + 1);

      if (_awaitedSize != 0) {
        if (framedLen >= _awaitedSize) {
          TransducerLogger.logFmt('Clearing _awaitedSize (was {0}) after receiving packet len {1}', [_awaitedSize, framedLen]);
          _awaitedSize = 0;
        } else {
          TransducerLogger.logFmt('Keeping _awaitedSize={0} (received framedLen={1}) to await more fragments', [_awaitedSize, framedLen]);
        }
      }

      tickRxCommand = DateTime.now().millisecondsSinceEpoch;
      waitAns = false;

      String lastPackage = framedAscii;

      bool isERRPacket = (framedBytes.length > 14 && framedBytes[13] == 0x45 && framedBytes[14] == 0x52);
      if (isERRPacket) {
        int errCode = 0;
        try {
          if (framedAscii.length >= 17) {
            final hexErr = framedAscii.substring(15, 17);
            errCode = int.parse(hexErr, radix: 16);
          }
        } catch (_) {
          errCode = 0;
        }
        TransducerLogger.logFmt('RX [ERR] packet - code={0} (will handle if known)', [errCode]);
        iConsecErrs++;

        // --- NEW: call interpretErrorResponse to get human-friendly description and action ---
        try {
          final Map<String, String> errInfo = interpretErrorResponse(framedAscii);
          TransducerLogger.logFmt('ERR interpreted -> code:{0} desc:{1} action:{2}', [errInfo['code'], errInfo['description'], errInfo['action']]);
          // Notify user-facing event with readable error (do not change other behavior)
          if (onEvent != null) onEvent!('ERR ${errInfo['code']}: ${errInfo['description']}');
        } catch (e) {
          TransducerLogger.logException(e, 'interpretErrorResponse call');
        }
        // --- end NEW ---

        if (enableDummyInjection && errCode == 0x03) {
          TransducerLogger.log('enableDummyInjection true and ERR03 -> injecting dummy ACKs where appropriate');
          if (_state == enumEState.eWaitingAquisitionConfig) {
            _injectDummyResponse("000008C4D0B4SA01");
          } else if (_state == enumEState.eWaitingAquisitionAdditionalConfig) {
            _injectDummyResponse("000008C4D0B4SB01");
          } else if (_state == enumEState.eWaitingAquisitionAdditional2Config) {
            _injectDummyResponse("000008C4D0B4SC01");
          }
        }

        if (errCode == 0x03) {
          if (_state == enumEState.eWaitingAquisitionAdditionalConfig || _state == enumEState.eMustSendAquisitionAdditionalConfig) {
            avoidSendAquisitionAdditionalConfig = true;
            mustSendAquisitionAdditionalConfig = false;
            TransducerLogger.log('Setting avoidSendAquisitionAdditionalConfig=true due to ERR03');
            if (_ackCompleters.containsKey('SB') && !_ackCompleters['SB']!.isCompleted) {
              _ackCompleters['SB']!.complete(false);
              TransducerLogger.log('ACK_COMPLETED: SB false (ERR03)');
            }
            if (onTransducerEvent != null) onTransducerEvent!(TransducerEvent.OldTransducerFirmwareDetected);
            _maybeEnableReadAfterConfigAck();
          } else if (_state == enumEState.eWaitingAquisitionAdditional2Config || _state == enumEState.eMustSendAquisitionAdditional2Config) {
            avoidSendAquisitionAdditional2Config = true;
            mustSendAquisitionAdditional2Config = false;
            TransducerLogger.log('Setting avoidSendAquisitionAdditional2Config=true due to ERR03');
            if (_ackCompleters.containsKey('SC') && !_ackCompleters['SC']!.isCompleted) {
              _ackCompleters['SC']!.complete(false);
              TransducerLogger.log('ACK_COMPLETED: SC false (ERR03)');
            }
            if (onTransducerEvent != null) onTransducerEvent!(TransducerEvent.OldTransducerFirmwareDetected);
            _maybeEnableReadAfterConfigAck();
          } else if (_state == enumEState.eWaitingAquisitionClickWrenchConfig || _state == enumEState.eMustSendAquisitionClickWrenchConfig) {
            avoidSendAquisitionClickWrenchConfig = true;
            mustSendAquisitionClickWrenchConfig = false;
            TransducerLogger.log('Setting avoidSendAquisitionClickWrenchConfig=true due to ERR03');
            if (_ackCompleters.containsKey('CS') && !_ackCompleters['CS']!.isCompleted) {
              _ackCompleters['CS']!.complete(false);
              TransducerLogger.log('ACK_COMPLETED: CS false (ERR03)');
            }
            if (onTransducerEvent != null) onTransducerEvent!(TransducerEvent.OldTransducerFirmwareDetected);
            _maybeEnableReadAfterConfigAck();
          } else {
            TransducerLogger.log('ERR 0x03 received in unknown state - enabling generic avoid flags for SB/SC/CS');
            avoidSendAquisitionAdditionalConfig = true;
            avoidSendAquisitionAdditional2Config = true;
            avoidSendAquisitionClickWrenchConfig = true;
            if (onTransducerEvent != null) onTransducerEvent!(TransducerEvent.OldTransducerFirmwareDetected);
            _maybeEnableReadAfterConfigAck();
          }
        }
        continue;
      }

      iConsecErrs = 0;

      // Handlers por comando
      if (com == 'ZO') {
        mustSendZeroTorque = false;
        mustSendZeroAngle = false;
        _suppressUntil = 0;
        if (_ackCompleters.containsKey('ZO') && !_ackCompleters['ZO']!.isCompleted) {
          _ackCompleters['ZO']!.complete(true);
          TransducerLogger.log('ACK_COMPLETED: ZO true');
        }
        _state = enumEState.eIdle;
        TransducerLogger.log('Parsed ZO response - cleared zero flags and suppression; ack completed if awaited');
        if (onEvent != null) onEvent!('ZO ack');
        continue;
      }

      if (com == 'SA') {
        mustSendAquisitionConfig = false;
        _state = enumEState.eIdle;
        if (_ackCompleters.containsKey('SA') && !_ackCompleters['SA']!.isCompleted) {
          _ackCompleters['SA']!.complete(true);
          TransducerLogger.log('ACK_COMPLETED: SA true');
        }
        TransducerLogger.log('Parsed SA response - mustSendAquisitionConfig cleared and ack completed if awaited');
        _maybeEnableReadAfterConfigAck();
        if (onEvent != null) onEvent!('SA ack');
        continue;
      }
      if (com == 'CS') {
        mustSendAquisitionClickWrenchConfig = false;
        _state = enumEState.eIdle;
        if (_ackCompleters.containsKey('CS') && !_ackCompleters['CS']!.isCompleted) {
          _ackCompleters['CS']!.complete(true);
          TransducerLogger.log('ACK_COMPLETED: CS true');
        }
        TransducerLogger.log('Parsed CS response - mustSendAquisitionClickWrenchConfig cleared and ack completed if awaited');
        _maybeEnableReadAfterConfigAck();
        if (onEvent != null) onEvent!('CS ack');
        continue;
      }
      if (com == 'SB') {
        mustSendAquisitionAdditionalConfig = false;
        _state = enumEState.eIdle;
        if (_ackCompleters.containsKey('SB') && !_ackCompleters['SB']!.isCompleted) {
          _ackCompleters['SB']!.complete(true);
          TransducerLogger.log('ACK_COMPLETED: SB true');
        }
        TransducerLogger.log('Parsed SB response - mustSendAquisitionAdditionalConfig cleared and ack completed if awaited');
        _maybeEnableReadAfterConfigAck();
        if (onEvent != null) onEvent!('SB ack');
        continue;
      }
      if (com == 'SC') {
        mustSendAquisitionAdditional2Config = false;
        _state = enumEState.eIdle;
        if (_ackCompleters.containsKey('SC') && !_ackCompleters['SC']!.isCompleted) {
          _ackCompleters['SC']!.complete(true);
          TransducerLogger.log('ACK_COMPLETED: SC true');
        }
        TransducerLogger.log('Parsed SC response - mustSendAquisitionAdditional2Config cleared and ack completed if awaited');
        _maybeEnableReadAfterConfigAck();
        if (onEvent != null) onEvent!('SC ack');
        continue;
      }

      // Parsing por estados
      if (_state == enumEState.eWaitingID) {
        if (com == 'ID') {
          if (lastPackage.length >= 13) {
            _id = lastPackage.substring(1, 13);
            mustSendGetID = false;
            mustSendRequestInformation = true;
            if (onEvent != null) onEvent!('ID_RECEIVED');
            TransducerLogger.logFmt('Parsed ID -> {0}', [_id]);
          }
        }
      } else if (_state == enumEState.eWaitingDeviceStatus) {
        if (com == 'DS') {
          try {
            DebugInformation dbg = DebugInformation();
            if (lastPackage.length >= 53) {
              dbg.State = int.parse(lastPackage.substring(15, 17), radix: 16);
              dbg.Error = int.parse(lastPackage.substring(17, 19), radix: 16);
              dbg.Temp_mC = int.parse(lastPackage.substring(19, 23), radix: 16);
              dbg.Interface = int.parse(lastPackage.substring(23, 25), radix: 16);
              dbg.PowerSource = int.parse(lastPackage.substring(25, 27), radix: 16);
              dbg.PowerState = int.parse(lastPackage.substring(27, 29), radix: 16);
              dbg.AnalogPowerState = int.parse(lastPackage.substring(29, 31), radix: 16);
              dbg.EncoderPowerState = int.parse(lastPackage.substring(31, 33), radix: 16);
              dbg.PowerVoltage_mV = int.parse(lastPackage.substring(33, 37), radix: 16);
              dbg.AutoPowerOFFSpan_s = int.parse(lastPackage.substring(37, 41), radix: 16);
              dbg.ResetReason = int.parse(lastPackage.substring(41, 45), radix: 16);
              dbg.AliveTime_s = int.parse(lastPackage.substring(45, 53), radix: 16);
              dbg.TorqueConversionFactor = torqueConversionFactor;
              dbg.AngleConversionFactor = angleConversionFactor;
            }
            if (onDebugInformation != null) onDebugInformation!(dbg);
            tickDeviceStatus = DateTime.now().millisecondsSinceEpoch;
            TransducerLogger.log('Parsed DS (device status)');
            if (onEvent != null) onEvent!('DS parsed');
          } catch (e) {
            TransducerLogger.logException(e, 'parse DS');
          }
        }
      } else if (_state == enumEState.eWaitingGetStatus) {
        if (com == 'LS') {
          try {
            int ackSt = int.parse(lastPackage.substring(15, 17), radix: 16);
            if (ackSt == eAquisitionState.Finished.index) {
              mustSendGetChartBlock = true;
              TransducerLogger.log('LS indicates acquisition finished -> mustSendGetChartBlock=true');
              if (onEvent != null) onEvent!('LS: finished');
            }
          } catch (e) {
            TransducerLogger.logException(e, 'parse LS');
          }
        }
      } else if (_state == enumEState.eWaitingAnswerReadCommand) {
        if (com == 'TQ') {
          try {
            final torqueHex = lastPackage.substring(15, 23);
            final angleHex = lastPackage.substring(23, 31);

            int torqueRaw = _parseSignedIntFromHex(torqueHex, bits: 32);
            int angleRaw = _parseSignedIntFromHex(angleHex, bits: 32);

            double torque = _truncateTo3Decimals(_adToNm(torqueRaw));
            double angle = _convertAngleFromBus(angleRaw);

            DataResult dr = DataResult();
            dr.Torque = torque;
            dr.Angle = angle;
            if (onDataResult != null) onDataResult!(dr);
            _state = enumEState.eWaitBetweenReads;
            TransducerLogger.logFmt('Parsed TQ torque={0} angle={1}', [torque, angle]);
            if (onEvent != null) onEvent!('TQ parsed torque=$torque angle=$angle');
          } catch (e) {
            TransducerLogger.logException(e, 'parse TQ');
          }
        }
      } else if (_state == enumEState.eWaitAnswerRequestInformation) {
        if (com == 'DI') {
          try {
            DataInformation di = DataInformation();
            if (lastPackage.length >= 91) {
              di.hardID = lastPackage.substring(15, 23).trim();
              di.model = lastPackage.substring(23, 55).trim();
              di.hw = lastPackage.substring(55, 59).trim();
              di.fw = lastPackage.substring(59, 63).trim();
              try {
                di.communicationType = int.parse(lastPackage.substring(71, 75), radix: 16);
              } catch (_) {
                di.communicationType = 0;
              }
              try {
                torqueConversionFactor = int.parse(lastPackage.substring(75, 83), radix: 16) * 0.000000000001;
              } catch (_) {
                torqueConversionFactor = 1.0;
              }
              try {
                angleConversionFactor = int.parse(lastPackage.substring(83, 91), radix: 16) * 0.001;
              } catch (_) {
                angleConversionFactor = 1.0;
              }
              di.torqueConversionFactor = torqueConversionFactor;
              di.angleConversionFactor = angleConversionFactor;
            }
            if (onDataInformation != null) onDataInformation!(di);
            mustSendRequestInformation = false;
            TransducerLogger.log('Parsed DI and fired onDataInformation');
            if (onEvent != null) onEvent!('DI parsed');
          } catch (e) {
            TransducerLogger.logException(e, 'parse DI');
          }
        }
      } else if (_state == enumEState.eWaitingCounters) {
        if (com == 'RC') {
          try {
            CountersInformation info = CountersInformation();
            int iCycles = int.parse(lastPackage.substring(15, 23), radix: 16);
            info.cycles = (iCycles == 0xFFFFFFFF ? 0 : iCycles).toString();
            int iOvershuts = int.parse(lastPackage.substring(23, 31), radix: 16);
            info.overshuts = (iOvershuts == 0xFFFFFFFF ? 0 : iOvershuts).toString();
            int number = int.parse(lastPackage.substring(31, 39), radix: 16);
            info.higherOvershut = _adToNm(number).toStringAsFixed(3);
            int add1 = int.parse(lastPackage.substring(39, 47), radix: 16);
            int add2 = int.parse(lastPackage.substring(47, 55), radix: 16);
            info.additional1 = (add1 == 0xFFFFFFFF ? 0 : add1).toString();
            info.additional2 = (add2 == 0xFFFFFFFF ? 0 : add2).toString();
            if (onCountersInformation != null) onCountersInformation!(info);
            mustSendGetCounters = false;
            TransducerLogger.log('Parsed RC counters');
            if (onEvent != null) onEvent!('RC parsed');
          } catch (e) {
            TransducerLogger.logException(e, 'parse RC');
          }
        }
      } else if (_state == enumEState.eWaitingChartBlock) {
        if (com == 'GD') {
          try {
            _parseGDFromBytes(Uint8List.fromList(framedBytes));
          } catch (e) {
            TransducerLogger.logException(e, 'parse GD - delegation to _parseGDFromBytes failed');
          }
        }
      }
    }
  } // fim _onData

  // ----------------------------
  // Helpers / Utilities

  int _parseSignedIntFromHex(String hex, {int bits = 32}) {
    int v = int.parse(hex, radix: 16);
    final int msbMask = 1 << (bits - 1);
    final int fullMask = 1 << bits;
    if ((v & msbMask) != 0) {
      v = v - fullMask;
    }
    return v;
  }

  int _indexOf(List<int> data, int v, {int start = 0}) {
    for (int i = start; i < data.length; i++) {
      if (data[i] == v) return i;
    }
    return -1;
  }

  int _indexOfSequence(List<int> data, List<int> seq, {int start = 0}) {
    if (seq.isEmpty) return -1;
    for (int i = start; i <= data.length - seq.length; i++) {
      bool ok = true;
      for (int j = 0; j < seq.length; j++) {
        if (data[i + j] != seq[j]) {
          ok = false;
          break;
        }
      }
      if (ok) return i;
    }
    return -1;
  }

  // ----- NEW: byte-based GD parser -----
  void _parseGDFromBytes(Uint8List framedBytes) {
    try {
      final int gdIdx = _indexOfSequence(framedBytes, ['G'.codeUnitAt(0), 'D'.codeUnitAt(0)]);
      if (gdIdx < 0) {
        TransducerLogger.log('parseGDFromBytes: sequence "GD" not found in framedBytes');
        return;
      }

      int sampleStart = gdIdx + 2;

      final int endInclusive = framedBytes.length - 3; // last data byte
      if (sampleStart > endInclusive) {
        TransducerLogger.logFmt('parseGDFromBytes: nothing to parse sampleStart={0} endInclusive={1}', [sampleStart, endInclusive]);
        return;
      }

      int parsedSamples = 0;
      for (int i = sampleStart; i + 4 <= endInclusive; i += 5) {
        final int b0 = framedBytes[i] & 0xFF;
        final int b1 = framedBytes[i + 1] & 0xFF;
        final int b2 = framedBytes[i + 2] & 0xFF;
        final int b3 = framedBytes[i + 3] & 0xFF;
        final int b4 = framedBytes[i + 4] & 0xFF;

        final bool bcomplete = (b0 & 0x80) == 0x80;

        int iaux = ((b0 & 0x7F) << 16) | (b1 << 8) | b2;

        if (bcomplete) {
          iaux |= (0xFF << 24);
          iaux = iaux.toSigned(32);
        }

        int iaux2 = ((b3 << 8) | b4) & 0xFFFF;
        if ((iaux2 & 0x8000) != 0) {
          iaux2 = iaux2 - 0x10000;
        }

        final double torque = _truncateTo3Decimals(_adToNm(iaux));
        final double angle = _convertAngleFromBus(iaux2);

        final DataResult dr = DataResult();
        dr.Torque = torque;
        dr.Angle = angle;
        dr.Type = 'TV';
        dr.SampleTime = _testeResultsList.length * acquisitionTimeStep_ms;
        _testeResultsList.add(dr);

        if (onDataResult != null) onDataResult!(dr);

        parsedSamples++;
      }

      TransducerLogger.logFmt('parseGDFromBytes: parsed {0} samples', [parsedSamples]);

      try {
        if (onTesteResult != null) {
          onTesteResult!(_testeResultsList);
        }
      } catch (e) {
        TransducerLogger.logException(e, '_parseGDFromBytes onTesteResult callback');
      }

      _testeResultsList = [];
      mustSendGetChartBlock = false;
      _state = enumEState.eMustSendReadCommand;
      TransducerLogger.log('Parsed GD block and emitted TesteResult (via _parseGDFromBytes)');
      if (onEvent != null) onEvent!('GD parsed samples=$parsedSamples');
    } catch (ex, st) {
      TransducerLogger.logException(ex, 'parseGDFromBytes');
      TransducerLogger.log('stack: $st');
    }
  }

  double _adToNm(int ad) {
    return ad * torqueConversionFactor;
  }

  int _nmToAd(double nm) {
    if (torqueConversionFactor == 0) return nm.toInt();
    return (nm / torqueConversionFactor).toInt();
  }

  double _truncateTo3Decimals(double v) {
    return (v * 1000).truncateToDouble() / 1000.0;
  }

  double _convertAngleFromBus(int n) {
    return n * angleConversionFactor;
  }

  int _convertAngleToBus(double angle) {
    if (angleConversionFactor == 0) return angle.toInt();
    return (angle / angleConversionFactor).toInt();
  }

  String _limitToHex8(int v) => v.toRadixString(16).padLeft(8, '0').toUpperCase();
  String _limitToHex4(int v) => v.toRadixString(16).padLeft(4, '0').toUpperCase();
  String _limitToHex2(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();

  int _thresholdToAd(double threshold) {
    return _nmToAd(threshold);
  }

  String _portIndexToHex(int idx) => idx.toRadixString(16).padLeft(2, '0');

  String _padHex(String s, int length) => s.padLeft(length, '0');

  // ----------------------------
  // CRC helpers
  String _makeCRCFromBytes(List<int> payloadBytes) {
    final sb = StringBuffer();
    for (var c in payloadBytes) {
      int k = 128;
      for (int j = 0; j < 8; j++) {
        sb.write(((c & k) == 0) ? '0' : '1');
        k = k >> 1;
      }
    }
    final bitStr = sb.toString();

    final crc = List<int>.filled(8, 0);
    for (int i = 0; i < bitStr.length; i++) {
      int doInvert = (bitStr[i] == '1') ? (crc[7] ^ 1) : crc[7];
      crc[7] = crc[6];
      crc[6] = crc[5];
      crc[5] = crc[4] ^ doInvert;
      crc[4] = crc[3];
      crc[3] = crc[2];
      crc[2] = crc[1] ^ doInvert;
      crc[1] = crc[0];
      crc[0] = doInvert;
    }
    int res0 = crc[4] + crc[5] * 2 + crc[6] * 4 + crc[7] * 8 + '0'.codeUnitAt(0);
    int res1 = crc[0] + crc[1] * 2 + crc[2] * 4 + crc[3] * 8 + '0'.codeUnitAt(0);
    if (res0 > '9'.codeUnitAt(0)) res0 += ('A'.codeUnitAt(0) - '9'.codeUnitAt(0) - 1);
    if (res1 > '9'.codeUnitAt(0)) res1 += ('A'.codeUnitAt(0) - '9'.codeUnitAt(0) - 1);
    return String.fromCharCode(res0) + String.fromCharCode(res1);
  }

  // For debug: get hex string of bytes
  String _toHex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');

  // Helper to inject a dummy response (used only when enableDummyInjection==true)
  void _injectDummyResponse(String payloadWithoutCRCAndBrackets) {
    try {
      final payloadBytes = latin1.encode(payloadWithoutCRCAndBrackets);
      final crc = _makeCRCFromBytes(payloadBytes);
      final builder = BytesBuilder();
      builder.addByte(0x5B);
      builder.add(payloadBytes);
      builder.add(latin1.encode(crc));
      builder.addByte(0x5D);
      final injected = Uint8List.fromList(builder.toBytes());
      TransducerLogger.logFmt('Injecting dummy response: {0}', [latin1.decode(injected, allowInvalid: true)]);
      _onData(injected);
    } catch (e) {
      TransducerLogger.logException(e, '_injectDummyResponse');
    }
  }

  Future<void> dispose() async {
    _userInitiatedStop = true;
    try {
      await _internalStopService();
    } catch (_) {}
  }
}

// Interpretador de ER (Dart) - cole em phoenix_transducer.dart
// Recebe payload ascii (ex: "ER03") ou a string framedAscii (ex: "[00000F311550ER03C4]")
// Retorna Map com codigo, descricao e recomendaçao de ação
Map<String, String> interpretErrorResponse(String framedAscii) {
  // Garantir que temos a parte útil: localizar 'ER' no frame
  String s = framedAscii;
  // Se o frame inclui colchetes e campos maiores, extraímos substring 'ERxx' se existir
  int erPos = s.indexOf('ER');
  if (erPos == -1) {
    return {
      'code': 'NONE',
      'description': 'Sem ER no frame',
      'action': 'Nenhuma ação específica'
    };
  }
  // Tentar extrair 4 caracteres (ER + 2 dígitos), se possível
  String errCode;
  if (erPos + 4 <= s.length) {
    errCode = s.substring(erPos, erPos+4); // ex: "ER03"
  } else {
    errCode = s.substring(erPos); // fallback
  }

  switch (errCode) {
    case 'ER01':
      return {
        'code': 'ER01',
        'description': 'CRC inválido (pacote corrompido ou modificado durante a transmissão).',
        'action': 'Descartar o pacote; opcionalmente reenviar o comando (com limite de retries) e logar o evento.'
      };
    case 'ER02':
      return {
        'code': 'ER02',
        'description': 'Erro de sintaxe (parâmetros no formato/tamanho incorreto ou valores fora do intervalo).',
        'action': 'Não reenviar automaticamente; revisar e corrigir parâmetros antes de tentar novamente. Mostrar aviso ao usuário.'
      };
    case 'ER03':
      return {
        'code': 'ER03',
        'description': 'Comando inválido ou não reconhecido pelo firmware.',
        'action': 'Verificar o payload enviado; provavelmente erro na construção do comando. Não reenviar automaticamente.'
      };
    case 'ER04':
      return {
        'code': 'ER04',
        'description': 'Dispositivo não pronto (p.ex.: operação solicitada enquanto aquisições estão em curso).',
        'action': 'Aguardar estado apropriado (poll DS/LS) e tentar novamente; ou executar fluxo de inicialização adequado.'
      };
    default:
      return {
        'code': errCode,
        'description': 'Código ER desconhecido (não documentado no firmware analisado).',
        'action': 'Logar e não reenviar; reportar para analise. Pode ser extension futura.'
      };
  }
}

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