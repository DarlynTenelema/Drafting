import 'dart:convert';
import 'api_client.dart';
import '../models/fanart_model.dart';

class FanartService {
  Future<List<FanartModel>> getFanarts() async {
    try {
      final response = await ApiClient.get('/api/v1/content/approved?type=fanarts', authenticated: true);
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => FanartModel.fromJson(json)).toList();
      } else {
        throw ApiException('Failed to load fanarts: ${response.statusCode}');
      }
    } catch (e) {
      throw ApiException(e.toString());
    }
  }

  Future<List<FanartModel>> fetchMyFanarts() async {
    try {
      final response = await ApiClient.get('/api/v1/content/my_fanarts', authenticated: true);
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => FanartModel.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<bool> deleteFanart(String id) async {
    try {
      final response = await ApiClient.delete('/api/v1/content/fanart?id=$id', authenticated: true);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>> purchaseFanart(String fanartId) async {
    try {
      final response = await ApiClient.post(
        '/api/v1/finance/fanart/purchase',
        body: {'fanart_id': fanartId},
        authenticated: true,
      );
      if (response.statusCode != 200) {
        final data = jsonDecode(response.body);
        return {'success': false, 'message': data['message'] ?? 'Failed to purchase fanart'};
      }
      return {'success': true};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> uploadFanart(String title, double priceCoin, String imagePath, {String tags = ''}) async {
    try {
      final response = await ApiClient.multipartPost(
        '/api/v1/content/fanart',
        fields: {
          'title': title,
          'price_coin': priceCoin.toString(),
          if (tags.isNotEmpty) 'tags': tags,
        },
        fileField: 'image',
        filePath: imagePath,
        authenticated: true,
      );
      if (response.statusCode != 200 && response.statusCode != 201) {
        return {'success': false, 'message': 'Error from server: ${response.statusCode}'};
      }
      return {'success': true};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> toggleLike(String fanartId) async {
    try {
      final response = await ApiClient.post(
        '/api/v1/interaction/fanart/like',
        body: {'fanart_id': fanartId},
        authenticated: true,
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return {'is_liked': false, 'total_likes': 0};
    } catch (e) {
      return {'is_liked': false, 'total_likes': 0};
    }
  }

  Future<bool> checkPurchase(String fanartId) async {
    try {
      final response = await ApiClient.get(
        '/api/v1/finance/fanart/check_purchase?fanart_id=$fanartId',
        authenticated: true,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['has_purchased'] == true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> postComment(String fanartId, String content) async {
    try {
      final response = await ApiClient.post(
        '/api/v1/interaction/comment',
        body: {
          'content_id': fanartId,
          'content_type': 'fanart',
          'content': content,
        },
        authenticated: true,
      );
      return response.statusCode == 201;
    } catch (e) {
      return false;
    }
  }
}
