import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'session_service.dart';

class ApiClient {
  ApiClient._();

  static Future<http.Response> post(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = false,
    String? sessionToken,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    if (authenticated) {
      final token = sessionToken ?? await SessionService.getSessionToken();
      if (token == null || token.isEmpty) {
        throw ApiException('No hay sesión activa.', statusCode: 401);
      }
      headers['Authorization'] = 'Bearer $token';
    }

    return http.post(
      AppConfig.apiUri(path),
      headers: headers,
      body: body == null ? null : jsonEncode(body),
    );
  }

  static Future<http.Response> get(
    String path, {
    bool authenticated = false,
    String? sessionToken,
  }) async {
    final headers = <String, String>{};

    if (authenticated) {
      final token = sessionToken ?? await SessionService.getSessionToken();
      if (token == null || token.isEmpty) {
        throw ApiException('No hay sesión activa.', statusCode: 401);
      }
      headers['Authorization'] = 'Bearer $token';
    }

    return http.get(AppConfig.apiUri(path), headers: headers);
  }
  static Future<http.Response> put(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = false,
    String? sessionToken,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    if (authenticated) {
      final token = sessionToken ?? await SessionService.getSessionToken();
      if (token == null || token.isEmpty) {
        throw ApiException('No hay sesión activa.', statusCode: 401);
      }
      headers['Authorization'] = 'Bearer $token';
    }

    return http.put(
      AppConfig.apiUri(path),
      headers: headers,
      body: body == null ? null : jsonEncode(body),
    );
  }

  static Future<http.Response> delete(
    String path, {
    bool authenticated = false,
    String? sessionToken,
  }) async {
    final headers = <String, String>{};

    if (authenticated) {
      final token = sessionToken ?? await SessionService.getSessionToken();
      if (token == null || token.isEmpty) {
        throw ApiException('No hay sesión activa.', statusCode: 401);
      }
      headers['Authorization'] = 'Bearer $token';
    }

    return http.delete(AppConfig.apiUri(path), headers: headers);
  }

  static Future<http.Response> multipartPost(
    String path, {
    required Map<String, String> fields,
    required String fileField,
    required String filePath,
    bool authenticated = false,
  }) async {
    final uri = AppConfig.apiUri(path);
    final request = http.MultipartRequest('POST', uri);

    request.fields.addAll(fields);

    if (filePath.isNotEmpty) {
      request.files.add(await http.MultipartFile.fromPath(fileField, filePath));
    }

    if (authenticated) {
      final token = await SessionService.getSessionToken();
      if (token == null || token.isEmpty) {
        throw ApiException('No hay sesión activa.', statusCode: 401);
      }
      request.headers['Authorization'] = 'Bearer $token';
    }

    final streamedResponse = await request.send();
    return await http.Response.fromStream(streamedResponse);
  }
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}
