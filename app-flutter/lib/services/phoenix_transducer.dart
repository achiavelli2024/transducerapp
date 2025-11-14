// lib/services/phoenix_transducer.dart
// PhoenixTransducer - V15 -> corrigido parsing signed 32-bit para torque/angle (V16 minimal)
// - Mantive TODO o restante do comportamento (reconexão, ERR==3 handling, dispatcher, etc).
// - Correção: converter campos hex para signed 32-bit antes de aplicar fatores de conversão.
// - Comentários explicativos incluídos.

// IMPORTANTE: Substitua este arquivo pelo existente e faça full restart do app:
// flutter clean && flutter pub get && flutter run

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

  int DEF_TIMESPAN_BETWEENREADS = 100; // intervalo padrão entre leituras (ms)
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

  PhoenixTransducer();

  // ----------------------------
  // Public API
  // ----------------------------
  Future<void> startService(String ip, int port) async {
    _ip = ip;
    _port = port;
    _userInitiatedStop = false; // mark that connection is user-requested active
    TransducerLogger.logFmt('startService requested: {0}:{1}', [ip, port]);
    await _internalStartServiceEth();
    _startDispatcherTimer();
  }

  Future<void> stopService() async {
    TransducerLogger.log('stopService called');
    _userInitiatedStop = true; // don't reconnect
    await _internalStopService();
  }

  Future<void> startCommunication() async {
    mustSendGetID = true;
    mustSendGetCounters = true;
    TransducerLogger.log('startCommunication: MustSendGetID & MustSendGetCounters set');
  }

  void requestInformation() {
    mustSendRequestInformation = true;
    TransducerLogger.log('requestInformation: MustSendRequestInformation set');
  }

  // startReadData: handshake; doesn't enable mustSendReadData immediately.
  void startReadData() {
    captureNewTightening = true;
    TransducerLogger.log('startReadData called: startReadRequested = true (waiting SA/CS ACKs)');
    startReadRequested = true;
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
  }

  void setZeroTorque() {
    mustSendZeroTorque = true;
    final now = DateTime.now().millisecondsSinceEpoch;
    _suppressUntil = now + 300;
    TransducerLogger.logFmt('setZeroTorque called - suppression until {0}', [_suppressUntil]);
  }

  void setZeroAngle() {
    mustSendZeroAngle = true;
    final now = DateTime.now().millisecondsSinceEpoch;
    _suppressUntil = now + 300;
    TransducerLogger.logFmt('setZeroAngle called - suppression until {0}', [_suppressUntil]);
  }

  void setTorqueOffset(double offset) {
    mustSendTorqueOffset = true;
    torqueOffset = offset;
    TransducerLogger.logFmt('setTorqueOffset: {0}', [offset]);
  }

  // ----------------------------
  // setTestParameter: VERSÃO COMPLETA (equivalente ao overload mais completo do C#)
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
    // Store SA params
    acquisitionToolType = toolType;
    acquisitionThreshold = threshold;
    acquisitionThresholdEnd = thresholdEnd;
    acquisitionTimeoutEnd_ms = timeoutEndMs;
    acquisitionTimeStep_ms = timeStepMs;
    acquisitionFilterFrequency = filterFrequency;
    acquisitionDir = direction;

    // Store TesteType and NominalTorque
    acquisitionTestType = type;
    acquisitionNominalTorque = nominalTorque;

    // Store SB params
    acquisitionTorqueTarget = torqueTarget;
    acquisitionTorqueMin = torqueMin;
    acquisitionTorqueMax = torqueMax;
    acquisitionAngleTarget = angleTarget;
    acquisitionAngleMin = angleMin;
    acquisitionAngleMax = angleMax;
    acquisitionDelayToDetectFirstPeak_ms = delayToDetectFirstPeakMs;
    acquisitionTimeToIgnoreNewPeakAfterFinalThreshold_ms = timeToIgnoreNewPeakAfterFinalThresholdMs;

    // set flags so dispatcher will send SA then CS then SB/SC accordingly
    mustSendAquisitionConfig = true;
    mustSendAquisitionAdditionalConfig = true;
    mustSendAquisitionAdditional2Config = true;

    // Keep DataInformation object for compatibility if needed
    if (info != null) {
      TransducerLogger.log('setTestParameter received DataInformation (not required to build SA/SB here)');
    }

    TransducerLogger.logFmt('setTestParameter stored: TesteType={0} NominalTorque={1} Threshold={2} torqueTarget={3} angleTarget={4}',
        [type.toString(), nominalTorque, threshold, torqueTarget, angleTarget]);
  }

  // Wrappers for overloads
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
      thresholdEnd: 0,
      timeoutEndMs: 1,
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

  Future<void> setTestParameterMedium(
      DataInformation? info,
      TesteType type,
      ToolType toolType,
      double nominalTorque,
      double threshold,
      double thresholdEnd,
      int timeoutEndMs,
      int timeStepMs,
      int filterFrequency,
      eDirection direction,
      ) {
    return setTestParameter(
      info,
      type,
      toolType,
      nominalTorque,
      threshold,
      thresholdEnd: thresholdEnd,
      timeoutEndMs: timeoutEndMs,
      timeStepMs: timeStepMs,
      filterFrequency: filterFrequency,
      direction: direction,
    );
  }

  // ClickWrench implementation (underscore style) - preserves earlier implementation
  void setTestParameter_ClickWrench(int fallPercentage, int risePercentage, int minTimeBetweenPulsesMs) {
    clickFall = fallPercentage;
    clickRise = risePercentage;
    clickMinTime_ms = minTimeBetweenPulsesMs;
    mustSendAquisitionClickWrenchConfig = true;
    TransducerLogger.logFmt('setTestParameter_ClickWrench stored fall={0} rise={1} minMs={2}', [fallPercentage, risePercentage, minTimeBetweenPulsesMs]);
  }

  // Backwards-compatible camelCase wrapper (connect_page.dart calls this)
  void setTestParameterClickWrench(int fallPercentage, int risePercentage, int minTimeBetweenPulsesMs) {
    try {
      setTestParameter_ClickWrench(fallPercentage, risePercentage, minTimeBetweenPulsesMs);
    } catch (e, st) {
      TransducerLogger.logException(e, 'setTestParameterClickWrench wrapper');
    }
  }

  // Helper: if startReadRequested was waiting for config ACKs, enable read if no more pending config flags.
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
          });
        }
      }
    } catch (e) {
      TransducerLogger.logException(e, '_maybeEnableReadAfterConfigAck');
    }
  }

  // ----------------------------
  // initRead synchronous sequence: ZO torque -> ZO angle -> CS -> SA -> delay -> StartReadData
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
      // close existing socket if any (defensive)
      if (_socket != null) {
        try {
          await _socket!.close();
        } catch (_) {}
        _socket = null;
      }
      TransducerLogger.logFmt('Connecting to {0}:{1}', [_ip, _port]);
      _socket = await Socket.connect(_ip, _port, timeout: const Duration(seconds: 5));
      _isConnected = true;
      _reconnectAttempts = 0; // reset backoff counter
      TransducerLogger.log('Socket connected');
      // set up listener
      _socket!.listen(_onData, onDone: _onDone, onError: _onSocketError, cancelOnError: false);
      tickDeviceStatus = DateTime.now().millisecondsSinceEpoch;
    } catch (ex) {
      _isConnected = false;
      TransducerLogger.logException(ex, '_internalStartServiceEth');
      if (onError != null) onError!(101);
      // schedule reconnect (only if user did not request stop)
      if (!_userInitiatedStop) {
        _scheduleReconnect();
      }
    }
  }

  Future<void> _internalStopService() async {
    try {
      TransducerLogger.log('Internal stop service - closing socket');
      _userInitiatedStop = true; // signal that this stop was requested by user
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
    }
  }

  // Called when remote closes the socket
  void _onDone() {
    _isConnected = false;
    TransducerLogger.log('Socket onDone - connection closed by remote');
    // Inform UI
    if (onEvent != null) onEvent!('socket_done');
    // don't emit OldTransducerFirmwareDetected here (that was incorrect before)
    if (onError != null) onError!(103);

    // If the user didn't intentionally stop, try to reconnect automatically
    if (!_userInitiatedStop) {
      TransducerLogger.log('Socket closed by remote; scheduling reconnect attempts.');
      _scheduleReconnect();
    }
  }

  void _onSocketError(Object err) {
    _isConnected = false;
    TransducerLogger.logException(err, '_onSocketError');
    if (onError != null) onError!(102);

    // Attempt reconnect unless user explicitly stopped
    if (!_userInitiatedStop) {
      TransducerLogger.log('_onSocketError: scheduling reconnect attempts (not user-initiated)');
      _scheduleReconnect();
    }
  }

  // Schedule reconnect with exponential backoff (non-blocking)
  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      TransducerLogger.logFmt('Max reconnect attempts ({0}) reached - will not try further', [_maxReconnectAttempts]);
      return;
    }
    _reconnectAttempts++;
    final delayMs = _baseReconnectDelayMs * (1 << (_reconnectAttempts - 1)); // exponential backoff: 500,1000,2000...
    final cappedDelay = delayMs > 10000 ? 10000 : delayMs; // cap at 10s
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
          // Restart dispatcher if needed
          if (_dispatcherTimer == null) _startDispatcherTimer();
        } else {
          TransducerLogger.log('Reconnect attempt did not succeed (socket not connected)');
          _scheduleReconnect(); // try again until max attempts
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
        // Keep V15 behavior for read loop (we already corrected in earlier change to allow repeat reads).
        if (_state != enumEState.eWaitingAnswerReadCommand &&
            (_state != enumEState.eWaitBetweenReads || (now - tickRxCommand >= DEF_TIMESPAN_BETWEENREADS))) {
          _state = enumEState.eMustSendReadCommand;
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
          _sendCommand(_padHex(_portIndexToHex(_portIndex()), 2) + '0000000000ID');
          break;
        case enumEState.eMustSendReadCommand:
          _state = enumEState.eWaitingAnswerReadCommand;
          tickTxCommand = DateTime.now().millisecondsSinceEpoch;
          _sendCommand(_id + 'TQ');
          TransducerLogger.logFmt('TQ requested (tickTxCommand={0})', [tickTxCommand]);
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
          _sendCommand(sSA);
          break;
        case enumEState.eMustSendAquisitionClickWrenchConfig:
          _state = enumEState.eWaitingAquisitionClickWrenchConfig;
          String sCS = _id +
              'CS' +
              _limitToHex2(clickFall) +
              _limitToHex2(clickRise) +
              _limitToHex2(clickMinTime_ms);
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
          _sendCommand(sSB);
          break;
        case enumEState.eMustSendAquisitionAdditional2Config:
          _state = enumEState.eWaitingAquisitionAdditional2Config;
          String sSC = _id +
              'SC' +
              _limitToHex4(acquisitionDelayToDetectFirstPeak_ms) +
              _limitToHex4(acquisitionTimeToIgnoreNewPeakAfterFinalThreshold_ms) +
              '000000000000000000000000000000000000000000000000';
          _sendCommand(sSC);
          break;
        case enumEState.eMustSendGetCounters:
          _state = enumEState.eWaitingCounters;
          _sendCommand(_id + 'RC');
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
  void _sendCommand(String cmd, {int awaitedSize = 0}) {
    if (!_isConnected || _socket == null) {
      TransducerLogger.log('SendCommand: not connected');
      if (onError != null) onError!(105);
      return;
    }
    try {
      String crc = _makeCRC(cmd);
      String frame = '[$cmd$crc]';
      _awaitedSize = awaitedSize;
      waitAns = true;
      final bytes = utf8.encode(frame);
      TransducerLogger.logTx('FRAME', frame);
      _socket!.add(bytes);
      tickTxCommand = DateTime.now().millisecondsSinceEpoch;
    } catch (e) {
      TransducerLogger.logException(e, '_sendCommand');
      if (onError != null) onError!(106);
    }
  }

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
  // RX parsing (full parser preserved; adapted to use DataInformation from models/data_information.dart)
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
        } else {
          return;
        }
      }

      int framedLen = bspend - bspini + 1;
      if (framedLen < 5) {
        _rxBuffer.removeRange(0, bspend + 1);
        return;
      }

      int payloadEndExclusive = bspend - 2;
      if (payloadEndExclusive <= bspini + 1) {
        _rxBuffer.removeRange(0, bspend + 1);
        return;
      }
      List<int> payloadBytes = _rxBuffer.sublist(bspini + 1, payloadEndExclusive);
      String payloadStr;
      try {
        payloadStr = utf8.decode(payloadBytes, allowMalformed: true);
      } catch (_) {
        payloadStr = String.fromCharCodes(payloadBytes);
      }

      String crcRecv = '';
      try {
        crcRecv = utf8.decode(_rxBuffer.sublist(bspend - 2, bspend), allowMalformed: true);
      } catch (_) {
        crcRecv = String.fromCharCodes(_rxBuffer.sublist(bspend - 2, bspend));
      }

      String crcCalc;
      try {
        crcCalc = _makeCRC(payloadStr);
      } catch (_) {
        crcCalc = '';
      }

      bool validCmd = false;
      if (crcCalc == crcRecv) validCmd = true;
      else if (_awaitedSize != 0 && DEF_IGNOREGRAPHCRC) validCmd = true;

      if (!validCmd) {
        if (_rxBuffer.length > bspend + 1) {
          _rxBuffer.removeRange(0, bspend + 1);
          iConsecErrs++;
          continue;
        } else {
          return;
        }
      }

      List<int> framedBytes = _rxBuffer.sublist(bspini, bspend + 1);
      String framedAscii;
      try {
        framedAscii = utf8.decode(framedBytes, allowMalformed: true);
      } catch (_) {
        framedAscii = String.fromCharCodes(framedBytes);
      }

      TransducerLogger.logFmt('PARSER framed ascii: {0}', [framedAscii]);

      _rxBuffer.removeRange(0, bspend + 1);

      tickRxCommand = DateTime.now().millisecondsSinceEpoch;
      waitAns = false;

      String com = '';
      if (framedBytes.length > 14) {
        try {
          com = utf8.decode(framedBytes.sublist(13, 15), allowMalformed: true);
        } catch (_) {
          com = String.fromCharCodes(framedBytes.sublist(13, 15));
        }
      }

      String lastPackage = framedAscii;

      bool isERRPacket = (framedBytes.length > 14 && framedBytes[13] == 0x45 && framedBytes[14] == 0x52);
      if (isERRPacket) {
        // Parse the error code and take corrective action when appropriate (mimic C# behavior)
        int errCode = 0;
        try {
          // error code typically is the two hex chars after 'ER' (positions 15..17 in ASCII framed string)
          if (framedAscii.length >= 17) {
            final hexErr = framedAscii.substring(15, 17);
            errCode = int.parse(hexErr, radix: 16);
          }
        } catch (_) {
          errCode = 0;
        }
        TransducerLogger.logFmt('RX [ERR] packet - code={0} (will handle if known)', [errCode]);
        iConsecErrs++;

        // If device returns ERR==3 after SB/SC/CS attempts it often means "old firmware / unsupported field".
        // In C# code they avoid sending SB/SC/CS afterwards and continue. We replicate that behaviour.
        if (errCode == 0x03) {
          // If we were waiting for SB acknowledge, avoid SB from now on
          if (_state == enumEState.eWaitingAquisitionAdditionalConfig || _state == enumEState.eMustSendAquisitionAdditionalConfig) {
            TransducerLogger.log('ERR 0x03 on SB -> setting avoidSendAquisitionAdditionalConfig = true and clearing mustSend flag');
            avoidSendAquisitionAdditionalConfig = true;
            mustSendAquisitionAdditionalConfig = false;
            // If someone is waiting for ack (ack completer), complete with false to unblock initRead callers.
            if (_ackCompleters.containsKey('SB') && !_ackCompleters['SB']!.isCompleted) {
              _ackCompleters['SB']!.complete(false);
            }
            // Notify typed event (old firmware)
            if (onTransducerEvent != null) onTransducerEvent!(TransducerEvent.OldTransducerFirmwareDetected);
            // Try to enable read if startReadRequested was waiting
            _maybeEnableReadAfterConfigAck();
          } else if (_state == enumEState.eWaitingAquisitionAdditional2Config || _state == enumEState.eMustSendAquisitionAdditional2Config) {
            TransducerLogger.log('ERR 0x03 on SC -> setting avoidSendAquisitionAdditional2Config = true and clearing mustSend flag');
            avoidSendAquisitionAdditional2Config = true;
            mustSendAquisitionAdditional2Config = false;
            if (_ackCompleters.containsKey('SC') && !_ackCompleters['SC']!.isCompleted) {
              _ackCompleters['SC']!.complete(false);
            }
            if (onTransducerEvent != null) onTransducerEvent!(TransducerEvent.OldTransducerFirmwareDetected);
            _maybeEnableReadAfterConfigAck();
          } else if (_state == enumEState.eWaitingAquisitionClickWrenchConfig || _state == enumEState.eMustSendAquisitionClickWrenchConfig) {
            TransducerLogger.log('ERR 0x03 on CS -> setting avoidSendAquisitionClickWrenchConfig = true and clearing mustSend flag');
            avoidSendAquisitionClickWrenchConfig = true;
            mustSendAquisitionClickWrenchConfig = false;
            if (_ackCompleters.containsKey('CS') && !_ackCompleters['CS']!.isCompleted) {
              _ackCompleters['CS']!.complete(false);
            }
            if (onTransducerEvent != null) onTransducerEvent!(TransducerEvent.OldTransducerFirmwareDetected);
            _maybeEnableReadAfterConfigAck();
          } else {
            // Generic: if we don't know which config was expected, try to avoid SB/SC to be safe.
            TransducerLogger.log('ERR 0x03 received in unknown state - enabling generic avoid flags for SB/SC');
            avoidSendAquisitionAdditionalConfig = true;
            avoidSendAquisitionAdditional2Config = true;
            avoidSendAquisitionClickWrenchConfig = true;
            if (onTransducerEvent != null) onTransducerEvent!(TransducerEvent.OldTransducerFirmwareDetected);
            _maybeEnableReadAfterConfigAck();
          }
        }

        // For ERR packets we don't treat them as fatal, simply continue parsing next frames.
        continue;
      }

      iConsecErrs = 0;

      // -----------------------
      // ZO handling
      if (com == 'ZO') {
        mustSendZeroTorque = false;
        mustSendZeroAngle = false;
        _suppressUntil = 0;
        if (_ackCompleters.containsKey('ZO') && !_ackCompleters['ZO']!.isCompleted) {
          _ackCompleters['ZO']!.complete(true);
        }
        _state = enumEState.eIdle;
        TransducerLogger.log('Parsed ZO response - cleared zero flags and suppression; ack completed if awaited');
        continue;
      }

      // SA / CS / SB / SC
      if (com == 'SA') {
        mustSendAquisitionConfig = false;
        _state = enumEState.eIdle;
        if (_ackCompleters.containsKey('SA') && !_ackCompleters['SA']!.isCompleted) _ackCompleters['SA']!.complete(true);
        TransducerLogger.log('Parsed SA response - mustSendAquisitionConfig cleared and ack completed if awaited');
        // After SA ack check enabling read
        _maybeEnableReadAfterConfigAck();
        continue;
      }
      if (com == 'CS') {
        mustSendAquisitionClickWrenchConfig = false;
        _state = enumEState.eIdle;
        if (_ackCompleters.containsKey('CS') && !_ackCompleters['CS']!.isCompleted) _ackCompleters['CS']!.complete(true);
        TransducerLogger.log('Parsed CS response - mustSendAquisitionClickWrenchConfig cleared and ack completed if awaited');
        _maybeEnableReadAfterConfigAck();
        continue;
      }
      if (com == 'SB') {
        mustSendAquisitionAdditionalConfig = false;
        _state = enumEState.eIdle;
        if (_ackCompleters.containsKey('SB') && !_ackCompleters['SB']!.isCompleted) _ackCompleters['SB']!.complete(true);
        TransducerLogger.log('Parsed SB response - mustSendAquisitionAdditionalConfig cleared and ack completed if awaited');
        _maybeEnableReadAfterConfigAck();
        continue;
      }
      if (com == 'SC') {
        mustSendAquisitionAdditional2Config = false;
        _state = enumEState.eIdle;
        if (_ackCompleters.containsKey('SC') && !_ackCompleters['SC']!.isCompleted) _ackCompleters['SC']!.complete(true);
        TransducerLogger.log('Parsed SC response - mustSendAquisitionAdditional2Config cleared and ack completed if awaited');
        _maybeEnableReadAfterConfigAck();
        continue;
      }

      // -----------------------
      // ID / DS / TQ / DI / RC / GD / LS parsing
      // We'll keep behavior aligned with the C# parsing performed earlier.
      if (_state == enumEState.eWaitingID) {
        if (com == 'ID') {
          if (lastPackage.length >= 13) {
            _id = lastPackage.substring(1, 13);
            mustSendGetID = false;
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
            }
          } catch (e) {
            TransducerLogger.logException(e, 'parse LS');
          }
        }
      } else if (_state == enumEState.eWaitingAnswerReadCommand) {
        if (com == 'TQ') {
          try {
            // ---------- CRUCIAL FIX ----------
            // Interpret torque & angle fields as SIGNED 32-bit integers (two's complement),
            // then apply conversion factors. This matches the C# behaviour and avoids huge positive values.
            //
            // In the framed ascii:
            //  - ID: positions 1..12
            //  - COM: positions 13..14 ('TQ')
            //  - torque hex: positions 15..22 (8 hex chars)
            //  - angle  hex: positions 23..30 (8 hex chars)
            //
            // Convert both as signed32 to match device encoding.
            //
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
          } catch (e) {
            TransducerLogger.logException(e, 'parse TQ');
          }
        }
      } else if (_state == enumEState.eWaitAnswerRequestInformation) {
        if (com == 'DI') {
          try {
            DataInformation di = DataInformation();
            // Map fields from the DI packet to your DataInformation model.
            // The original parser used fixed substrings; we keep that mapping but adapt to the Dart DataInformation fields.
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
          } catch (e) {
            TransducerLogger.logException(e, 'parse RC');
          }
        }
      } else if (_state == enumEState.eWaitingChartBlock) {
        if (com == 'GD') {
          try {
            int end = framedBytes.length - 3;
            for (int i = 15; i <= end - 1; i += 5) {
              if (i + 4 >= framedBytes.length) break;
              int b0 = framedBytes[i];
              int b1 = framedBytes[i + 1];
              int b2 = framedBytes[i + 2];
              bool bcomplete = (b0 & 0x80) == 0x80;
              int iaux = ((b0 << 16) & 0xFF0000) + ((b1 << 8) & 0xFF00) + (b2 & 0xFF);
              if (bcomplete) {
                iaux |= (255 << 24);
              }
              int b3 = framedBytes[i + 3];
              int b4 = framedBytes[i + 4];
              bool b2complete = (b3 & 0x80) == 0x80;
              int iaux2 = ((b3 << 8) & 0xFF00) + (b4 & 0xFF);
              if (b2complete) {
                iaux2 = -(65536 - iaux2);
              }
              DataResult res = DataResult();
              res.Torque = (_truncateTo3Decimals(_adToNm(iaux)));
              res.Angle = _convertAngleFromBus(iaux2);
              res.Type = 'TV';
              res.SampleTime = _testeResultsList.length * acquisitionTimeStep_ms;
              _testeResultsList.add(res);
            }
            if (onTesteResult != null) onTesteResult!(_testeResultsList);
            _testeResultsList = [];
            mustSendGetChartBlock = false;
            _state = enumEState.eMustSendReadCommand;
            TransducerLogger.log('Parsed GD block and emitted TesteResult');
          } catch (e) {
            TransducerLogger.logException(e, 'parse GD');
          }
        }
      }
    }
  }

  // ----------------------------
  // Helpers / Utilities

  // Converte hex string (por exemplo 'FFFFFCA0') para inteiro signed com 'bits' bits (ex: 32).
  // Isso trata complemento de dois corretamente, evitando interpretações como grande unsigned.
  int _parseSignedIntFromHex(String hex, {int bits = 32}) {
    int v = int.parse(hex, radix: 16);
    final int msbMask = 1 << (bits - 1);
    final int fullMask = 1 << bits;
    if ((v & msbMask) != 0) {
      // valor negativo em complemento de dois
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

  int _portIndex() {
    return 0;
  }

  String _portIndexToHex(int idx) => idx.toRadixString(16).padLeft(2, '0');

  String _padHex(String s, int length) => s.padLeft(length, '0');

  String _makeCRC(String cmd) {
    StringBuffer bitString = StringBuffer();
    for (int i = 0; i < cmd.length; i++) {
      int c = cmd.codeUnitAt(i);
      int k = 128;
      for (int j = 0; j < 8; j++) {
        if ((c & k) == 0) bitString.write('0');
        else bitString.write('1');
        k = k >> 1;
      }
    }

    List<int> CRC = List<int>.filled(8, 0);

    String bits = bitString.toString();
    for (int i = 0; i < bits.length; i++) {
      int DoInvert = (bits[i] == '1') ? (CRC[7] ^ 1) : CRC[7];
      int newCRC7 = CRC[6];
      int newCRC6 = CRC[5];
      int newCRC5 = CRC[4] ^ DoInvert;
      int newCRC4 = CRC[3];
      int newCRC3 = CRC[2];
      int newCRC2 = CRC[1] ^ DoInvert;
      int newCRC1 = CRC[0];
      int newCRC0 = DoInvert;
      CRC[7] = newCRC7;
      CRC[6] = newCRC6;
      CRC[5] = newCRC5;
      CRC[4] = newCRC4;
      CRC[3] = newCRC3;
      CRC[2] = newCRC2;
      CRC[1] = newCRC1;
      CRC[0] = newCRC0;
    }

    int res0 = CRC[4] + CRC[5] * 2 + CRC[6] * 4 + CRC[7] * 8 + '0'.codeUnitAt(0);
    int res1 = CRC[0] + CRC[1] * 2 + CRC[2] * 4 + CRC[3] * 8 + '0'.codeUnitAt(0);
    if (res0 > '9'.codeUnitAt(0)) res0 += ('A'.codeUnitAt(0) - '9'.codeUnitAt(0) - 1);
    if (res1 > '9'.codeUnitAt(0)) res1 += ('A'.codeUnitAt(0) - '9'.codeUnitAt(0) - 1);
    return String.fromCharCode(res0) + String.fromCharCode(res1);
  }

  Future<void> dispose() async {
    _userInitiatedStop = true;
    await _internalStopService();
  }
}