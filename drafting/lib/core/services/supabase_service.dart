import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static final _supabase = Supabase.instance.client;

  static Future<String> uploadFile(String bucket, String fileName, File file) async {
    final path = fileName;
    await _supabase.storage.from(bucket).upload(path, file);
    return path;
  }

  static String getPublicUrl(String bucket, String path) {
    return _supabase.storage.from(bucket).getPublicUrl(path);
  }
}
