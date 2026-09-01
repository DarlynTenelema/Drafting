import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:io';
import 'api_client.dart';
import 'supabase_service.dart';

class EntrepreneurService {
  static final EntrepreneurService _instance = EntrepreneurService._internal();
  factory EntrepreneurService() => _instance;
  EntrepreneurService._internal();

  /// Create a Group Plan
  Future<Map<String, dynamic>> createGroup(String name, String plan, List<String> invites, String productName, String productImage, String purchaseToken) async {
    try {
      final response = await ApiClient.post(
        '/groups/create',
        body: {
          'name': name,
          'description': 'Group plan: $plan',
          'subscription_plan': plan,
          'product_name': productName,
          'product_image': productImage,
          'purchase_token': purchaseToken,
          'invites': invites,
        },
        authenticated: true,
      );
        if (response.statusCode == 200 || response.statusCode == 201) {
          final data = jsonDecode(response.body);
          if (data['success'] == true || data['success'] == null) return {'success': true};
          return {'success': false, 'error': data['message'] ?? 'Error desconocido', 'banned': data['banned'] ?? false};
        }
        try {
          final data = jsonDecode(response.body);
          return {'success': false, 'error': data['message'] ?? 'Error ${response.statusCode}', 'banned': data['banned'] ?? false};
        } catch (_) {
          return {'success': false, 'error': 'Error ${response.statusCode}: ${response.body}'};
        }
    } catch (e) {
      debugPrint("Error creating group: $e");
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Create an OTP Profile (Creator Profile)
  Future<Map<String, dynamic>> createOTPProfile(String championName, String plan, String productName, String productImage, String purchaseToken) async {
    try {
      final response = await ApiClient.post(
        '/group/otp/create', // It's mapped to CreateOTPProfile in backend routing
        body: {
          'champion_name': championName,
          'description': 'OTP plan: $plan',
          'subscription_plan': plan,
          'product_name': productName,
          'product_image': productImage,
          'purchase_token': purchaseToken,
        },
        authenticated: true,
      );
        if (response.statusCode == 200 || response.statusCode == 201) {
          final data = jsonDecode(response.body);
          if (data['success'] == true || data['success'] == null) return {'success': true};
          return {'success': false, 'error': data['message'] ?? 'Error desconocido', 'banned': data['banned'] ?? false};
        }
        try {
          final data = jsonDecode(response.body);
          return {'success': false, 'error': data['message'] ?? 'Error ${response.statusCode}', 'banned': data['banned'] ?? false};
        } catch (_) {
          return {'success': false, 'error': 'Error ${response.statusCode}: ${response.body}'};
        }
    } catch (e) {
      debugPrint("Error creating OTP profile: $e");
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Save Champion Data Rules to the Entrepreneur's Group/Profile
  Future<Map<String, dynamic>> saveChampionData(String championName, String rules) async {
    try {
      final response = await ApiClient.post(
        '/groups/champion',
        body: {
          'champion_name': championName,
          'rules': rules,
        },
        authenticated: true,
      );
      
      try {
        final data = jsonDecode(response.body);
        if (response.statusCode == 200 || response.statusCode == 201) {
          if (data['success'] == true || data['success'] == null) {
            return {'success': true};
          }
        }
        return {
          'success': false,
          'message': data['message'] ?? 'Error del servidor: ${response.statusCode}',
          'banned': data['banned'] ?? false,
        };
      } catch (_) {
        if (response.statusCode == 200 || response.statusCode == 201) {
          return {'success': true};
        }
        return {'success': false, 'message': 'Error from server: ${response.statusCode}'};
      }
    } catch (e) {
      debugPrint("Error saving champion data: $e");
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Update and Train AI Model (Gemini verification in backend)
  Future<Map<String, dynamic>> saveAIModel(Map<String, dynamic> data) async {
    try {
      final response = await ApiClient.post(
        '/creator/ai-model',
        body: data,
        authenticated: true,
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {'success': false, 'error': 'Failed to save model'};
    } catch (e) {
      debugPrint("Error saving AI model: $e");
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Get list of configured champions for this creator
  Future<List<String>> getMyChampions() async {
    try {
      final response = await ApiClient.get(
        '/groups/champions',
        authenticated: true,
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final list = data.map((e) => e.toString()).toList();
        if (list.isNotEmpty) return list;
      }
      return ['Ahri', 'Yasuo'];
    } catch (e) {
      debugPrint("Error getting my champions: $e");
      return ['Ahri', 'Yasuo'];
    }
  }
  /// Check if the user is eligible for the first month free
  Future<bool> checkFirstTimeEligibility() async {
    try {
      final response = await ApiClient.get(
        '/creator/eligibility',
        authenticated: true,
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['eligible'] == true;
      }
      return false;
    } catch (e) {
      debugPrint("Error checking eligibility: $e");
      return false;
    }
  }

  /// Upload product image to Supabase
  Future<String?> uploadProductImage(File imageFile, String userId) async {
    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_$userId.jpg';
      final path = await SupabaseService.uploadFile('store_products', fileName, imageFile).timeout(const Duration(seconds: 15));
      return SupabaseService.getPublicUrl('store_products', path);
    } catch (e) {
      debugPrint("Error uploading image: $e");
      return null;
    }
  }
}
