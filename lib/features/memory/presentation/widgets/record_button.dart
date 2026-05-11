import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/services/user_service.dart';
import '../../../../core/services/voice_record_service.dart';
import '../../../../shared/widgets/permission_dialogs.dart';
import 'waveform_widget.dart';

class RecordButton extends StatelessWidget {
  final void Function(Map<String, dynamic> memory) onRecordComplete;

  const RecordButton({super.key, required this.onRecordComplete});

  Future<void> _handleTap(BuildContext context) async {
    final svc = context.read<VoiceRecordService>();
    final userId = context.read<UserService>().userId;

    if (svc.state == RecordingState.idle) {
      await svc.startRecording();
      if (svc.lastError != null && context.mounted) {
        await showPermissionHelpDialog(
          context: context,
          title: '需要麦克风权限',
          message: '请允许小碎使用麦克风，这样才能录制你的语音记忆。如果系统没有弹出授权框，可能是之前已经拒绝过，需要到设置里重新开启。',
        );
      }
      return;
    }

    if (svc.state == RecordingState.recording) {
      final result = await svc.stopAndUpload(userId: userId);
      if (result != null) onRecordComplete(result);
      if (svc.lastError != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(svc.lastError!)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<VoiceRecordService>();
    final theme = Theme.of(context);

    final isRecording = svc.state == RecordingState.recording;
    final isProcessing = svc.state == RecordingState.processing;

    return GestureDetector(
      onTap: isProcessing ? null : () => _handleTap(context),
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
              ? [BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.5), blurRadius: 24, spreadRadius: 4)]
              : [],
        ),
        child: isProcessing
            ? const Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : isRecording
                ? WaveformWidget(
                    amplitudes: svc.amplitudeHistory,
                    color: Colors.white,
                  )
                : const Icon(Icons.mic, color: Colors.white, size: 32),
      ),
    );
  }
}
