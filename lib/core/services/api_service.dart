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
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 200) {
      throw Exception('add_memory failed ${streamed.statusCode}: $body');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> listMemories({
    String userId = 'default',
    int limit = 20,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/memories')
        .replace(queryParameters: {'user_id': userId, 'limit': '$limit'});
    final resp = await http.get(uri).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw Exception('list_memories failed ${resp.statusCode}');
    }
    return (jsonDecode(resp.body) as List).cast<Map<String, dynamic>>();
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
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }
}
