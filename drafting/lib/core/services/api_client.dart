import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'language_service.dart';
import 'session_service.dart';

class ApiClient {
  ApiClient._();

  /// Construye las cabeceras estándar (idioma, Content-Type y token Bearer si aplica)
  /// eliminando la duplicación en todos los métodos HTTP.
  static Future<Map<String, String>> _buildHeaders({
    bool authenticated = false,
    String? sessionToken,
    bool jsonContent = false,
  }) async {
    final headers = <String, String>{
      if (jsonContent) 'Content-Type': 'application/json',
      'Accept-Language': LanguageService.instance.currentLanguage,
    };

    if (authenticated) {
      final token = sessionToken ?? await SessionService.getSessionToken();
      if (token == null || token.isEmpty) {
        throw ApiException('No hay sesión activa.', statusCode: 401);
      }
      headers['Authorization'] = 'Bearer $token';
    }

    return headers;
  }

  static Future<http.Response> _handleRequest(Future<http.Response> Function() requestFunc) async {
    try {
      final response = await requestFunc().timeout(const Duration(seconds: 30));
      if (response.statusCode == 401) {
        await SessionService.clearSession();
      }
      return response;
    } on TimeoutException {
      throw ApiException(LanguageService.instance.tr('net_timeout'));
    } on SocketException {
      throw ApiException(LanguageService.instance.tr('net_offline'));
    } catch (e) {
      if (e.toString().contains('SocketException') || e.toString().contains('ClientException')) {
        throw ApiException(LanguageService.instance.tr('net_offline'));
      } else if (e.toString().contains('TimeoutException')) {
        throw ApiException(LanguageService.instance.tr('net_timeout'));
      }
      rethrow;
    }
  }

  static Future<http.Response> post(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = false,
    String? sessionToken,
  }) async {
    final headers = await _buildHeaders(
      authenticated: authenticated,
      sessionToken: sessionToken,
      jsonContent: true,
    );

    return _handleRequest(() => http.post(
      AppConfig.apiUri(path),
      headers: headers,
      body: body == null ? null : jsonEncode(body),
    ));
  }

  static Future<http.Response> get(
    String path, {
    bool authenticated = false,
    String? sessionToken,
  }) async {
    final headers = await _buildHeaders(
      authenticated: authenticated,
      sessionToken: sessionToken,
    );

    return _handleRequest(() => http.get(AppConfig.apiUri(path), headers: headers));
  }

  static Future<http.Response> put(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = false,
    String? sessionToken,
  }) async {
    final headers = await _buildHeaders(
      authenticated: authenticated,
      sessionToken: sessionToken,
      jsonContent: true,
    );

    return _handleRequest(() => http.put(
      AppConfig.apiUri(path),
      headers: headers,
      body: body == null ? null : jsonEncode(body),
    ));
  }

  static Future<http.Response> delete(
    String path, {
    bool authenticated = false,
    String? sessionToken,
  }) async {
    final headers = await _buildHeaders(
      authenticated: authenticated,
      sessionToken: sessionToken,
    );

    return _handleRequest(() => http.delete(AppConfig.apiUri(path), headers: headers));
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
    final headers = await _buildHeaders(authenticated: authenticated);
    request.headers.addAll(headers);
    request.fields.addAll(fields);

    if (filePath.isNotEmpty) {
      request.files.add(await http.MultipartFile.fromPath(fileField, filePath));
    }

    return _handleRequest(() async {
      final streamedResponse = await request.send();
      return await http.Response.fromStream(streamedResponse);
    });
  }
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}
