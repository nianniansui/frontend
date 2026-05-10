import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

/// Web 平台：用浏览器原生 fetch 读取 blob URL
Future<Uint8List> fetchBlobBytes(String url) async {
  final response = await web.window.fetch(url.toJS).toDart;
  final arrayBuffer = await response.arrayBuffer().toDart;
  return arrayBuffer.toDart.asUint8List();
}
