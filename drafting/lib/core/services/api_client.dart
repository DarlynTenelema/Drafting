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
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}
