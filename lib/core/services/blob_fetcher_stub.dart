import 'dart:typed_data';

/// iOS/非Web平台 stub — 不会被调用，仅满足编译器
Future<Uint8List> fetchBlobBytes(String url) {
  throw UnsupportedError('fetchBlobBytes is only supported on web');
}
