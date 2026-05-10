import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/services/user_service.dart';
import '../../../../core/services/voice_record_service.dart';
import 'waveform_widget.dart';

class RecordButton extends StatelessWidget {
  final void Function(Map<String, dynamic> memory) onRecordComplete;

  const RecordButton({super.key, required this.onRecordComplete});

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<VoiceRecordService>();
    final theme = Theme.of(context);

    final isRecording = svc.state == RecordingState.recording;
    final isProcessing = svc.state == RecordingState.processing;

    return GestureDetector(
      onTapDown: (_) async {
        if (svc.state == RecordingState.idle) {
          await svc.startRecording();
        }
      },
      onTapUp: (_) async {
        if (isRecording) {
          final userId = context.read<UserService>().userId;
          final result = await svc.stopAndUpload(userId: userId);
          if (result != null) onRecordComplete(result);
          if (svc.lastError != null && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(svc.lastError!)),
            );
          }
        }
      },
      onLongPressStart: (_) async {
        if (svc.state == RecordingState.idle) {
          await svc.startRecording();
        }
      },
      onLongPressEnd: (_) async {
        if (isRecording) {
          final userId = context.read<UserService>().userId;
          final result = await svc.stopAndUpload(userId: userId);
          if (result != null) onRecordComplete(result);
        }
      },
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
