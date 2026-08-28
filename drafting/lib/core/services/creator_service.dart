import 'dart:convert';
import 'api_client.dart';

class CreatorService {
  Future<Map<String, dynamic>?> getCreatorProfile() async {
    try {
      final response = await ApiClient.get('/api/v1/creator/profile', authenticated: true);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>> createCreatorProfile(String artistName, List<String> tags) async {
    try {
      final response = await ApiClient.post(
        '/api/v1/creator/profile',
        body: {
          'artist_name': artistName,
          'tags': tags.join(','),
        },
        authenticated: true,
      );
      
      if (response.statusCode == 201) {
        return {'success': true};
      } else {
        try {
          final data = jsonDecode(response.body);
          return {'success': false, 'message': data['message'] ?? 'Error al crear el perfil'};
        } catch (_) {
          return {'success': false, 'message': 'Error del servidor: ${response.statusCode}'};
        }
      }
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }
}
