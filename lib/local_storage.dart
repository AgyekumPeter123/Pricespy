import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

class LocalStorageService {
  /// Get the local path where we save chat media
  static Future<String> _getLocalPath() async {
    final directory = await getApplicationDocumentsDirectory();
    final mediaDir = Directory('${directory.path}/media');
    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }
    return mediaDir.path;
  }

  /// Check if a file exists locally based on its remote URL (using URL hash as filename)
  static Future<File?> getLocalFile(String remoteUrl) async {
    final path = await _getLocalPath();
    // Simple way to create a unique filename from URL
    final fileName = remoteUrl.hashCode.toString();
    final file = File('$path/$fileName');

    if (await file.exists()) {
      return file;
    }
    return null;
  }

  /// Download and Save file locally
  static Future<File?> downloadAndSave(String remoteUrl) async {
    try {
      final response = await http.get(Uri.parse(remoteUrl));
      if (response.statusCode == 200) {
        final path = await _getLocalPath();
        final fileName = remoteUrl.hashCode.toString();
        final file = File('$path/$fileName');
        return await file.writeAsBytes(response.bodyBytes);
      }
      return null;
    } catch (e) {
      print("Download failed: $e");
      return null;
    }
  }
}
