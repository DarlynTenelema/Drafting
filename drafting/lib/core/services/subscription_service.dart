import 'dart:convert';

import 'api_client.dart';

class SubscriptionStatus {
  final bool hasActiveSubscription;
  final bool globalFreeTrialActive;
  final bool canAccessService;
  final DateTime? endsAt;
  final String? planName;

  SubscriptionStatus({
    required this.hasActiveSubscription,
    required this.globalFreeTrialActive,
    required this.canAccessService,
    this.endsAt,
    this.planName,
  });

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) {
    return SubscriptionStatus(
      hasActiveSubscription: json['has_active_subscription'] == true,
      globalFreeTrialActive: json['global_free_trial_active'] == true,
      canAccessService: json['can_access_service'] == true,
      endsAt: json['ends_at'] != null ? DateTime.tryParse(json['ends_at'] as String) : null,
      planName: json['plan_name'] as String?,
    );
  }
}

class SubscriptionService {
  SubscriptionService._();

  static Future<SubscriptionStatus> getStatus({String? sessionToken}) async {
    final response = await ApiClient.get(
      '/api/v1/subscription/status',
      authenticated: true,
      sessionToken: sessionToken,
    );

    if (response.statusCode != 200) {
      throw ApiException('No se pudo obtener el estado de suscripción.', statusCode: response.statusCode);
    }

    return SubscriptionStatus.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<DateTime?> verifyPurchase({
    required String productId,
    required String purchaseToken,
    String? sessionToken,
  }) async {
    final response = await ApiClient.post(
      '/api/v1/subscription/verify',
      authenticated: true,
      sessionToken: sessionToken,
      body: {
        'product_id': productId,
        'purchase_token': purchaseToken,
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['ends_at'] != null) {
        return DateTime.tryParse(data['ends_at'] as String);
      }
      return null;
    }

    final message = response.body.isNotEmpty ? response.body : 'Verificación de compra fallida.';
    throw ApiException(message, statusCode: response.statusCode);
  }

  static Future<bool> subscribeCreator({
    required String subscriptionId,
    required String purchaseToken,
    required String creatorId,
    String? sessionToken,
  }) async {
    final response = await ApiClient.post(
      '/api/v1/finance/subscribe_creator',
      authenticated: true,
      sessionToken: sessionToken,
      body: {
        'subscription_id': subscriptionId,
        'purchase_token': purchaseToken,
        'creator_id': creatorId,
      },
    );

    if (response.statusCode == 200) {
      return true;
    }
    
    final message = response.body.isNotEmpty ? response.body : 'Verificación de suscripción al creador fallida.';
    throw ApiException(message, statusCode: response.statusCode);
  }

  static Future<bool> subscribeGroup({
    required String subscriptionId,
    required String purchaseToken,
    required String groupId,
    String? sessionToken,
  }) async {
    final response = await ApiClient.post(
      '/api/v1/finance/subscribe_group',
      authenticated: true,
      sessionToken: sessionToken,
      body: {
        'subscription_id': subscriptionId,
        'purchase_token': purchaseToken,
        'group_id': groupId,
      },
    );

    if (response.statusCode == 200) {
      return true;
    }
    
    final message = response.body.isNotEmpty ? response.body : 'Verificación de suscripción al grupo fallida.';
    throw ApiException(message, statusCode: response.statusCode);
  }

  static Future<List<dynamic>> getMyPackages({String? sessionToken}) async {
    final response = await ApiClient.get(
      '/api/v1/store/my_packages',
      authenticated: true,
      sessionToken: sessionToken,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    return [];
  }
}
