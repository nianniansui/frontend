import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'api_service.dart';

// Web 专用 blob fetch，通过条件导入隔离平台代码
import 'blob_fetcher_stub.dart'
    if (dart.library.js_interop) 'blob_fetcher_web.dart';

enum RecordingState { idle, recording, processing }

class VoiceRecordService extends ChangeNotifier {
  final AudioRecorder _recorder = AudioRecorder();
  final ApiService _api;

  RecordingState _state = RecordingState.idle;
  String? _lastError;
  String? _tempFilePath;

  final List<double> _amplitudeHistory = List.filled(20, 0.0);
  StreamSubscription<Amplitude>? _amplitudeSub;

  RecordingState get state => _state;
  String? get lastError => _lastError;
  bool get isRecording => _state == RecordingState.recording;
  List<double> get amplitudeHistory => List.unmodifiable(_amplitudeHistory);

  VoiceRecordService(this._api);

  Future<bool> requestPermission() async {
    if (kIsWeb) return await _recorder.hasPermission();
    final status = await Permission.microphone.request();
    return status.isGranted;
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
        final dir = await getTemporaryDirectory();
        _tempFilePath =
            '${dir.path}/xiaosui_${DateTime.now().millisecondsSinceEpoch}.wav';
        await _recorder.start(config, path: _tempFilePath!);
      }

      _state = RecordingState.recording;
      // Web 不支持 onAmplitudeChanged，只在原生平台启用波形
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

  Future<Map<String, dynamic>?> stopAndUpload({String userId = 'default'}) async {
    if (_state != RecordingState.recording) return null;

    _resetAmplitude();
    _state = RecordingState.processing;
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
        final file = File(_tempFilePath!);
        final result = await _api.addMemoryFromFile(
          file: file,
          mimeType: 'audio/wav',
          userId: userId,
        );
        await file.delete();
        _tempFilePath = null;
        return result;
      }
    } catch (e) {
      _lastError = '上传失败: $e';
      return null;
    } finally {
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
    _recorder.dispose();
    super.dispose();
  }
}
