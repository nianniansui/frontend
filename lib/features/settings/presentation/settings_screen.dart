import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/theme_service.dart';
import '../../../core/services/user_service.dart';
import '../../../core/db/memory_cache.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _recapEnabled = true;

  @override
  void initState() {
    super.initState();
    NotificationService.instance.isRecapEnabled().then((v) {
      if (mounted) setState(() => _recapEnabled = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeSvc = context.watch<ThemeService>();
    final userSvc = context.watch<UserService>();

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          const _SectionHeader(title: '外观'),
          _ThemeTile(
            label: '跟随系统',
            mode: ThemeMode.system,
            selected: themeSvc.mode == ThemeMode.system,
            icon: Icons.brightness_auto_outlined,
            onTap: () => themeSvc.setMode(ThemeMode.system),
          ),
          _ThemeTile(
            label: '浅色',
            mode: ThemeMode.light,
            selected: themeSvc.mode == ThemeMode.light,
            icon: Icons.light_mode_outlined,
            onTap: () => themeSvc.setMode(ThemeMode.light),
          ),
          _ThemeTile(
            label: '深色',
            mode: ThemeMode.dark,
            selected: themeSvc.mode == ThemeMode.dark,
            icon: Icons.dark_mode_outlined,
            onTap: () => themeSvc.setMode(ThemeMode.dark),
          ),
          const _SectionHeader(title: '提醒'),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('开启通知'),
            subtitle: Text(
              '让小碎在有日程或重要内容时提醒你',
              style: theme.textTheme.bodyMedium,
            ),
            onTap: () async {
              final ok = await NotificationService.instance.requestPermission();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(ok
                      ? '已开启通知权限'
                      : '请到 设置 → 小碎 → 通知 中手动开启'),
                ),
              );
              if (ok) {
                final api = context.read<ApiService>();
                await NotificationService.instance.syncFromServer(
                  api: api,
                  userId: userSvc.userId,
                );
              }
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.wb_sunny_outlined),
            title: const Text('每日回顾'),
            subtitle: Text(
              '每天早上挑一条旧记忆推送，让记过的事重新被想起',
              style: theme.textTheme.bodyMedium,
            ),
            value: _recapEnabled,
            onChanged: (v) async {
              setState(() => _recapEnabled = v);
              await NotificationService.instance.setRecapEnabled(v);
              if (v && context.mounted) {
                final api = context.read<ApiService>();
                await NotificationService.instance.syncFromServer(
                  api: api,
                  userId: userSvc.userId,
                );
              }
            },
          ),
          const _SectionHeader(title: '账号'),
          ListTile(
            leading: const Icon(Icons.fingerprint_outlined),
            title: const Text('匿名 ID'),
            subtitle: Text(
              userSvc.userId.isEmpty ? '加载中…' : userSvc.userId,
              style: theme.textTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const _SectionHeader(title: '数据'),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('清理本地缓存'),
            subtitle: Text('仅清除本机缓存和原音，云端记忆不会删除',
                style: theme.textTheme.bodyMedium),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('清理本地缓存？'),
                  content: const Text('云端记忆会保留，下次刷新时会重新下载。'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('取消'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('清理'),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                await MemoryCache().clearOld(userSvc.userId, days: 0);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已清理本地缓存')),
                );
              }
            },
          ),
          const _SectionHeader(title: '关于'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('小碎'),
            subtitle: Text('随口一记，随时找回。'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  final String label;
  final ThemeMode mode;
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;

  const _ThemeTile({
    required this.label,
    required this.mode,
    required this.selected,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: selected
          ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
          : null,
      onTap: onTap,
    );
  }
}
