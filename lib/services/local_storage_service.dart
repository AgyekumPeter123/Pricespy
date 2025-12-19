import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

class LocalStorageService {
  static Future<String> _getLocalPath() async {
    final directory = await getApplicationDocumentsDirectory();
    final mediaDir = Directory('${directory.path}/media');
    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }
    return mediaDir.path;
  }

  static Future<File?> getLocalFile(String remoteUrl) async {
    try {
      final path = await _getLocalPath();
      final fileName = remoteUrl.hashCode.toString();
      final file = File('$path/$fileName');
      if (await file.exists()) return file;
    } catch (e) {
      debugPrint("Error finding local file: $e");
    }
    return null;
  }

  static Future<File?> downloadAndSave(String remoteUrl) async {
    try {
      final response = await http.get(Uri.parse(remoteUrl));
      if (response.statusCode == 200) {
        final path = await _getLocalPath();
        final fileName = remoteUrl.hashCode.toString();
        final file = File('$path/$fileName');
        return await file.writeAsBytes(response.bodyBytes);
      }
    } catch (e) {
      debugPrint("Download failed: $e");
    }
    return null;
  }
}
