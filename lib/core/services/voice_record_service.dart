import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'api_service.dart';
import 'audio_storage.dart';

import 'blob_fetcher_stub.dart'
    if (dart.library.js_interop) 'blob_fetcher_web.dart';

enum RecordingState { idle, recording, processing }

/// 上传子阶段，用来把总流程拆成用户可感知的几步
enum ProcessingStage { uploading, transcribing, summarizing }

class VoiceRecordService extends ChangeNotifier {
  final AudioRecorder _recorder = AudioRecorder();
  final ApiService _api;

  RecordingState _state = RecordingState.idle;
  ProcessingStage _processingStage = ProcessingStage.uploading;
  String? _lastError;
  String? _tempFilePath;
  String? _lastRecordedFilename;

  final List<double> _amplitudeHistory = List.filled(20, 0.0);
  StreamSubscription<Amplitude>? _amplitudeSub;
  Timer? _stageTimer;

  RecordingState get state => _state;
  ProcessingStage get processingStage => _processingStage;
  String? get lastError => _lastError;
  bool get isRecording => _state == RecordingState.recording;
  List<double> get amplitudeHistory => List.unmodifiable(_amplitudeHistory);

  String get processingLabel {
    switch (_processingStage) {
      case ProcessingStage.uploading:
        return '上传中…';
      case ProcessingStage.transcribing:
        return '转写中…';
      case ProcessingStage.summarizing:
        return '整理摘要中…';
    }
  }

  VoiceRecordService(this._api);

  Future<bool> requestPermission() async {
    if (kIsWeb) return await _recorder.hasPermission();
    return _recorder.hasPermission();
  }

  Future<void> startRecording() async {
    _lastError = null;

    final granted = await requestPermission();
    if (!granted) {
      _lastError = '需要麦克风权限才能录音';
      notifyListeners();
      return;
    }

    try {
      final config = RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      );

      if (kIsWeb) {
        await _recorder.start(config, path: '');
      } else {
        final audioDirPath = await AudioStorage.audioDir();
        final filename = AudioStorage.newFileName();
        _tempFilePath = '$audioDirPath/$filename';
        _lastRecordedFilename = filename;
        await _recorder.start(config, path: _tempFilePath!);
      }

      _state = RecordingState.recording;
      if (!kIsWeb) {
        _amplitudeSub = _recorder
            .onAmplitudeChanged(const Duration(milliseconds: 80))
            .listen((amp) {
          final normalized = ((amp.current + 60) / 60).clamp(0.0, 1.0);
          _amplitudeHistory.removeAt(0);
          _amplitudeHistory.add(normalized);
          notifyListeners();
        });
      }
      notifyListeners();
    } catch (e) {
      _lastError = '录音启动失败: $e';
      notifyListeners();
    }
  }

  void _resetAmplitude() {
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    _amplitudeHistory.fillRange(0, _amplitudeHistory.length, 0.0);
  }

  /// 启动一个"阶段模拟器"，让用户感知从上传→转写→摘要的过程。
  /// 真实阶段无法从服务端推送，但按经验值在时间轴上切换文字比干等更友好。
  void _startStageTimers() {
    _processingStage = ProcessingStage.uploading;
    _stageTimer?.cancel();
    _stageTimer = Timer(const Duration(milliseconds: 1200), () {
      _processingStage = ProcessingStage.transcribing;
      notifyListeners();
      _stageTimer = Timer(const Duration(milliseconds: 2500), () {
        _processingStage = ProcessingStage.summarizing;
        notifyListeners();
      });
    });
  }

  void _stopStageTimers() {
    _stageTimer?.cancel();
    _stageTimer = null;
  }

  /// 停止录音并上传。返回服务端记录；原始音频路径通过 `_audio_path` 带回（仅原生端）。
  Future<Map<String, dynamic>?> stopAndUpload({String userId = 'default'}) async {
    if (_state != RecordingState.recording) return null;

    _resetAmplitude();
    _state = RecordingState.processing;
    _startStageTimers();
    notifyListeners();

    try {
      if (kIsWeb) {
        final blobUrl = await _recorder.stop();
        if (blobUrl == null || blobUrl.isEmpty) throw Exception('录音数据为空');
        final bytes = await fetchBlobBytes(blobUrl);
        return await _api.addMemoryFromBytes(
          audioBytes: bytes,
          mimeType: 'audio/wav',
          userId: userId,
        );
      } else {
        await _recorder.stop();
        if (_tempFilePath == null) throw Exception('录音文件路径为空');
        final localAudioPath = _tempFilePath!;
        final file = File(localAudioPath);
        final result = await _api.addMemoryFromFile(
          file: file,
          mimeType: 'audio/wav',
          userId: userId,
        );
        _tempFilePath = null;
        // 只挂文件名；绝对路径在 iOS 重装后会失效
        return {...result, 'audio_path': _lastRecordedFilename};
      }
    } catch (e) {
      _lastError = '上传失败: $e';
      // 上传失败时清理未成功的临时文件
      if (!kIsWeb && _tempFilePath != null) {
        final f = File(_tempFilePath!);
        if (await f.exists()) await f.delete();
        _tempFilePath = null;
      }
      return null;
    } finally {
      _stopStageTimers();
      _state = RecordingState.idle;
      notifyListeners();
    }
  }

  Future<void> cancelRecording() async {
    if (_state != RecordingState.recording) return;
    _resetAmplitude();
    await _recorder.cancel();
    if (_tempFilePath != null) {
      final f = File(_tempFilePath!);
      if (await f.exists()) await f.delete();
      _tempFilePath = null;
    }
    _state = RecordingState.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _amplitudeSub?.cancel();
    _stopStageTimers();
    _recorder.dispose();
    super.dispose();
  }
}
