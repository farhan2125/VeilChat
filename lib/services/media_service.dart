import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class MediaService {
  static String baseUrl = 'http://192.168.100.62:5001';

  static void updateBaseUrl(String newIp) {
    baseUrl = 'http://$newIp:5001';
  }

  static Future<String?> uploadEncryptedFile(File file) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/upload'));
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
      
      var response = await request.send();
      if (response.statusCode == 200) {
        var responseData = await response.stream.bytesToString();
        var json = jsonDecode(responseData);
        return json['filename'];
      }
    } catch (e) {
      debugPrint("❌ Media Upload Error: $e");
    }
    return null;
  }

  static Future<File?> downloadEncryptedFile(String filename, String savePath) async {
    try {
      // Use a client with longer timeout for large files
      final client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse('$baseUrl/download/$filename'));
        final streamedResponse = await client.send(request)
            .timeout(const Duration(seconds: 60));

        if (streamedResponse.statusCode == 200) {
          final bytes = await streamedResponse.stream
              .toBytes()
              .timeout(const Duration(seconds: 120));
          final file = File(savePath);
          await file.writeAsBytes(bytes);
          debugPrint("✅ Download complete: ${bytes.length} bytes");
          return file;
        } else {
          debugPrint("❌ Download failed with status \${streamedResponse.statusCode}");
        }
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint("❌ Media Download Error: \$e");
    }
    return null;
  }
}