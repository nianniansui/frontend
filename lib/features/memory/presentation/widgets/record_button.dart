import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../core/services/user_service.dart';
import '../../../../core/services/voice_record_service.dart';
import '../../../../shared/widgets/permission_dialogs.dart';
import 'waveform_widget.dart';

/// 中央录音按钮。支持两种交互：
/// - 短按：切换录音（开始 / 停止上传），适合长段记录
/// - 长按：按住说话（松开上传），符合中文用户直觉
class RecordButton extends StatefulWidget {
  final void Function(Map<String, dynamic> memory) onRecordComplete;

  const RecordButton({super.key, required this.onRecordComplete});

  @override
  State<RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<RecordButton> {
  bool _longPressMode = false;

  Future<void> _startIfIdle(BuildContext context) async {
    final svc = context.read<VoiceRecordService>();
    if (svc.state != RecordingState.idle) return;
    await svc.startRecording();
    if (!context.mounted) return;
    if (svc.lastError != null) {
      await showPermissionHelpDialog(
        context: context,
        title: '需要麦克风权限',
        message: '请允许小碎使用麦克风，这样才能录制你的语音记忆。如果系统没有弹出授权框，可能是之前已经拒绝过，需要到设置里重新开启。',
      );
    } else {
      HapticFeedback.mediumImpact();
    }
  }

  Future<void> _stopAndUpload(BuildContext context) async {
    final svc = context.read<VoiceRecordService>();
    final userId = context.read<UserService>().userId;
    if (svc.state != RecordingState.recording) return;
    HapticFeedback.lightImpact();
    final result = await svc.stopAndUpload(userId: userId);
    if (!context.mounted) return;
    if (result != null) widget.onRecordComplete(result);
    if (svc.lastError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(svc.lastError!)),
      );
    }
  }

  Future<void> _handleTap(BuildContext context) async {
    if (_longPressMode) {
      // 长按松手会同时触发 onLongPressEnd 和 onTap，避免二次处理
      _longPressMode = false;
      return;
    }
    final svc = context.read<VoiceRecordService>();
    if (svc.state == RecordingState.idle) {
      await _startIfIdle(context);
    } else if (svc.state == RecordingState.recording) {
      await _stopAndUpload(context);
    }
  }

  Future<void> _handleLongPressStart(BuildContext context) async {
    final svc = context.read<VoiceRecordService>();
    if (svc.state != RecordingState.idle) return;
    _longPressMode = true;
    await _startIfIdle(context);
  }

  Future<void> _handleLongPressEnd(BuildContext context) async {
    if (!_longPressMode) return;
    await _stopAndUpload(context);
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<VoiceRecordService>();
    final theme = Theme.of(context);

    final isRecording = svc.state == RecordingState.recording;
    final isProcessing = svc.state == RecordingState.processing;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isProcessing)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              svc.processingLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          )
        else if (isRecording)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _longPressMode ? '松开发送' : '点击结束',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        GestureDetector(
          onTap: isProcessing ? null : () => _handleTap(context),
          onLongPressStart: isProcessing
              ? null
              : (_) => _handleLongPressStart(context),
          onLongPressEnd: isProcessing
              ? null
              : (_) => _handleLongPressEnd(context),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: isRecording ? 88 : 72,
            height: isRecording ? 88 : 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isRecording
                  ? theme.colorScheme.primary
                  : theme.colorScheme.primary.withValues(alpha: 0.85),
              boxShadow: isRecording
                  ? [
                      BoxShadow(
                        color: theme.colorScheme.primary.withValues(alpha: 0.5),
                        blurRadius: 24,
                        spreadRadius: 4,
                      )
                    ]
                  : [],
            ),
            child: isProcessing
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : isRecording
                    ? WaveformWidget(
                        amplitudes: svc.amplitudeHistory,
                        color: Colors.white,
                      )
                    : const Icon(Icons.mic, color: Colors.white, size: 32),
          ),
        ),
      ],
    );
  }
}
