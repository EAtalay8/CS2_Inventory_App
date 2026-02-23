import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class LocalStorageService {
  static final LocalStorageService _instance = LocalStorageService._internal();
  factory LocalStorageService() => _instance;
  LocalStorageService._internal();

  Future<String> _getFilePath(String filename) async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/$filename';
  }

  Future<Map<String, dynamic>> loadData(String filename) async {
    try {
      final path = await _getFilePath(filename);
      final file = File(path);
      if (await file.exists()) {
        final content = await file.readAsString();
        return json.decode(content) as Map<String, dynamic>;
      }
    } catch (e) {
      print("Error loading $filename: $e");
    }
    return {};
  }

  Future<void> saveData(String filename, Map<String, dynamic> data) async {
    try {
      final path = await _getFilePath(filename);
      final file = File(path);
      await file.writeAsString(json.encode(data));
    } catch (e) {
      print("Error saving $filename: $e");
    }
  }
}
