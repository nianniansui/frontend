import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// 单例音频播放器，保证同时只有一条记忆在播放。
/// 目前仅原生端支持原音回放（Web 端不缓存原始 blob）。
class AudioPlayerService extends ChangeNotifier {
  static final AudioPlayerService instance = AudioPlayerService._();
  AudioPlayerService._() {
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _currentId = null;
        _player.seek(Duration.zero);
        _player.stop();
      }
      notifyListeners();
    });
  }

  final AudioPlayer _player = AudioPlayer();
  String? _currentId;

  bool get isPlaying => _player.playing;
  String? get currentId => _currentId;

  bool isPlayingId(String id) => _currentId == id && _player.playing;

  Future<void> toggle({required String id, required String path}) async {
    if (kIsWeb) return;
    if (_currentId == id && _player.playing) {
      await _player.pause();
      notifyListeners();
      return;
    }
    if (_currentId == id) {
      await _player.play();
      notifyListeners();
      return;
    }

    final file = File(path);
    if (!await file.exists()) {
      _currentId = null;
      notifyListeners();
      throw Exception('原音文件已丢失');
    }
    await _player.stop();
    await _player.setFilePath(path);
    _currentId = id;
    notifyListeners();
    await _player.play();
  }

  Future<void> stop() async {
    if (_currentId == null) return;
    await _player.stop();
    _currentId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
