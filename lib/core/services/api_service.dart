import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class ApiService {
  final String baseUrl;

  ApiService({this.baseUrl = 'http://localhost:8000'});

  Future<Map<String, dynamic>> addMemoryFromFile({
    required File file,
    required String mimeType,
    String userId = 'default',
  }) async {
    final bytes = await file.readAsBytes();
    return addMemoryFromBytes(
      audioBytes: bytes,
      mimeType: mimeType,
      userId: userId,
      filename: file.path.split('/').last,
    );
  }

  Future<Map<String, dynamic>> addMemoryFromBytes({
    required Uint8List audioBytes,
    required String mimeType,
    String userId = 'default',
    String filename = 'audio.wav',
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/add_memory');
    final request = http.MultipartRequest('POST', uri)
      ..fields['user_id'] = userId
      ..files.add(http.MultipartFile.fromBytes(
        'audio',
        audioBytes,
        filename: filename,
        contentType: MediaType.parse(mimeType),
      ));

    final streamed = await request.send().timeout(const Duration(seconds: 60));
    final bodyBytes = await streamed.stream.toBytes();

    if (streamed.statusCode != 200) {
      throw Exception(
        'add_memory failed ${streamed.statusCode}: ${utf8.decode(bodyBytes, allowMalformed: true)}',
      );
    }
    return jsonDecode(utf8.decode(bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> addMemoryText({
    required String text,
    String userId = 'default',
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/add_memory_text');
    final resp = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'text': text, 'user_id': userId}),
        )
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      throw Exception(
        'add_memory_text failed ${resp.statusCode}: ${utf8.decode(resp.bodyBytes, allowMalformed: true)}',
      );
    }
    return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> listMemories({
    String userId = 'default',
    int limit = 20,
    String? before,
  }) async {
    final params = {'user_id': userId, 'limit': '$limit'};
    if (before != null) params['before'] = before;
    final uri = Uri.parse('$baseUrl/api/v1/memories').replace(queryParameters: params);
    final resp = await http.get(uri).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw Exception('list_memories failed ${resp.statusCode}');
    }
    return (jsonDecode(utf8.decode(resp.bodyBytes)) as List)
        .cast<Map<String, dynamic>>();
  }

  Future<void> deleteMemory({
    required String memoryId,
    String userId = 'default',
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/memories/$memoryId')
        .replace(queryParameters: {'user_id': userId});
    final resp = await http.delete(uri).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw Exception('delete_memory failed ${resp.statusCode}');
    }
  }

  Future<Map<String, dynamic>> updateMemory({
    required String memoryId,
    String userId = 'default',
    String? summary,
    String? rawText,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/memories/$memoryId')
        .replace(queryParameters: {'user_id': userId});
    final payload = <String, dynamic>{};
    if (summary != null) payload['summary'] = summary;
    if (rawText != null) payload['raw_text'] = rawText;
    final resp = await http
        .patch(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw Exception('update_memory failed ${resp.statusCode}');
    }
    return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> search({
    required String query,
    String userId = 'default',
    int topK = 5,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/search');
    final resp = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'query': query, 'user_id': userId, 'top_k': topK}),
        )
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      throw Exception('search failed ${resp.statusCode}');
    }
    return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
  }
}
