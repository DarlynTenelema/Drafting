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

  /// Get all saved AI models (Database tab)
  Future<List<Map<String, dynamic>>> getAllAIModels() async {
    try {
      final response = await ApiClient.get(
        '/creator/ai-models',
        authenticated: true,
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data);
      }
      return [];
    } catch (e) {
      debugPrint("Error getting all AI models: $e");
      return [];
    }
  }

  /// Update an existing AI model
  Future<Map<String, dynamic>> updateAIModel(Map<String, dynamic> data) async {
    try {
      final response = await ApiClient.post(
        '/creator/ai-model/update',
        body: data,
        authenticated: true,
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {'success': false, 'error': 'Failed to update model'};
    } catch (e) {
      debugPrint("Error updating AI model: $e");
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Delete an AI model
  Future<Map<String, dynamic>> deleteAIModel(String championName) async {
    try {
      final response = await ApiClient.post(
        '/creator/ai-model/delete',
        body: {'champion_name': championName},
        authenticated: true,
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {'success': false, 'error': 'Failed to delete model'};
    } catch (e) {
      debugPrint("Error deleting AI model: $e");
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Toggle product visibility from the store
  Future<Map<String, dynamic>> toggleProductVisibility(bool isHidden) async {
    try {
      final response = await ApiClient.post(
        '/groups/update-visibility',
        body: {'is_hidden': isHidden},
        authenticated: true,
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {'success': false, 'error': 'Failed to update product visibility'};
    } catch (e) {
      debugPrint("Error toggling product visibility: $e");
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Update Group Settings (Name and Image)
  Future<Map<String, dynamic>> updateGroupSettings(String name, String? imagePath) async {
    try {
      String? uploadedImageUrl;
      if (imagePath != null && imagePath.isNotEmpty) {
        uploadedImageUrl = await uploadProductImage(File(imagePath), "creator_id_placeholder");
      }

      final body = {'name': name};
      if (uploadedImageUrl != null) {
        body['product_image'] = uploadedImageUrl;
      }

      final response = await ApiClient.post(
        '/groups/update-info',
        body: body,
        authenticated: true,
      );
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {'success': false, 'error': 'Failed to update group settings'};
    } catch (e) {
      debugPrint("Error updating group settings: $e");
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Check active subscriptions for the creator's product
  Future<Map<String, dynamic>> checkActiveSubscriptions() async {
    try {
      final response = await ApiClient.get(
        '/groups/active-subscriptions',
        authenticated: true,
      );
      if (response.statusCode == 200) {
        return json.decode(response.body); // e.g. {"hasActive": true, "lastEndDate": "2026-12-01T00:00:00Z"}
      }
      return {'hasActive': false, 'lastEndDate': null};
    } catch (e) {
      debugPrint("Error checking active subscriptions: $e");
      return {'hasActive': false, 'lastEndDate': null};
    }
  }

  /// Schedule product for deletion after a certain date
  Future<Map<String, dynamic>> scheduleProductDeletion(DateTime deletionDate) async {
    try {
      final response = await ApiClient.post(
        '/groups/schedule-deletion',
        body: {'deletion_date': deletionDate.toIso8601String()},
        authenticated: true,
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {'success': false, 'error': 'Failed to schedule deletion'};
    } catch (e) {
      debugPrint("Error scheduling deletion: $e");
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Delete product immediately
  Future<Map<String, dynamic>> deleteProductNow() async {
    try {
      final response = await ApiClient.post(
        '/groups/delete-now',
        body: {},
        authenticated: true,
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {'success': false, 'error': 'Failed to delete product'};
    } catch (e) {
      debugPrint("Error deleting product now: $e");
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

  /// Get available creator plans and their available slots
  Future<List<dynamic>> getCreatorPlans() async {
    try {
      final response = await ApiClient.get(
        '/creator/plans',
        authenticated: true,
      );
      if (response.statusCode == 200) {
        return json.decode(response.body) as List<dynamic>;
      }
      return [];
    } catch (e) {
      debugPrint("Error getting creator plans: $e");
      return [];
    }
  }

  /// Validate if an email exists for a group invite
  Future<bool> validateInviteEmail(String email) async {
    try {
      final response = await ApiClient.post(
        '/creator/validate-invite',
        authenticated: true,
        body: {'email': email},
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['valid'] == true;
      }
      return false;
    } catch (e) {
      debugPrint("Error validating invite email: $e");
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
