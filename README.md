# 小碎 Frontend

> 随口一记，随时找回。

Flutter 端，支持 iOS 和 Web。语音优先的"第二记忆"应用。

## 技术栈

| 层 | 技术 |
|---|---|
| 框架 | Flutter 3.x (Dart 3) |
| 状态管理 | Provider |
| 录音 | record ^6.0.0 |
| 本地缓存 | sqflite (iOS) / 内存 Map (Web) |
| 用户标识 | 匿名 UUID，SharedPreferences 持久化 |
| 网络 | http + http_parser |
| Web 音频 | dart:js_interop + package:web (blob URL fetch) |

## 目录结构

```
lib/
├── main.dart
├── core/
│   ├── db/
│   │   ├── local_db.dart              # SQLite 单例
│   │   └── memory_cache.dart          # 离线缓存 CRUD
│   └── services/
│       ├── api_service.dart           # HTTP 客户端
│       ├── user_service.dart          # 匿名 UUID 管理
│       ├── voice_record_service.dart  # 录音 + 上传
│       ├── blob_fetcher_web.dart      # Web blob URL → bytes
│       └── blob_fetcher_stub.dart     # 非 Web stub
├── features/
│   ├── memory/
│   │   └── presentation/
│   │       ├── screens/home_screen.dart
│   │       └── widgets/
│   │           ├── record_button.dart
│   │           ├── memory_card.dart
│   │           └── waveform_widget.dart
│   └── search/
│       └── presentation/search_screen.dart
└── shared/
    └── theme/app_theme.dart
```

## 本地运行

### 安装依赖

```bash
flutter pub get
cd ios && pod install && cd ..
```

### iOS（模拟器 / 真机）

```bash
flutter run
```

首次真机运行需在 Xcode 里配置 Developer Team（免费账号即可）。

### Web（开发模式）

```bash
flutter run -d chrome
```

### Web（生产，配合后端 docker-compose）

```bash
flutter build web --release
# 产物在 build/web/，由后端 nginx 容器托管
```

或使用根目录一键脚本：

```bash
./build_web.sh
```

## 核心功能

**语音录音**
- 点击 / 长按中央录音按钮开始录音
- iOS 录音中显示实时波形动画（20 帧滚动窗口）
- 松开后自动上传，后台完成 STT → 摘要 → 向量化 → 存储

**记忆流**
- 首页按时间倒序展示记忆卡片
- 先读本地缓存（即时显示），再请求 API 更新
- 断网时显示「离线模式」提示，仍可浏览历史记忆

**语义搜索**
- 支持文字输入和语音提问
- AI 结合时间戳返回最新状态，并展示相关原始记录

## 环境配置

Web 生产环境下 `baseUrl` 自动设为空串（走 nginx 反代），开发环境默认 `http://localhost:8000`。

如需修改后端地址，编辑 `lib/main.dart`：

```dart
final api = ApiService(
  baseUrl: kIsWeb ? '' : 'http://YOUR_SERVER:8000',
);
```

## iOS 权限

`ios/Runner/Info.plist` 已配置：
- `NSMicrophoneUsageDescription` — 麦克风权限
- `NSSpeechRecognitionUsageDescription` — 语音识别权限
