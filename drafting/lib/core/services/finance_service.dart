import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'api_client.dart';

class FinanceService extends ChangeNotifier {
  static final FinanceService _instance = FinanceService._internal();
  factory FinanceService() => _instance;
  FinanceService._internal();

  double _totalCoins = 0.0;
  double _totalUsd = 0.0;

  void reset() {
    _totalCoins = 0.0;
    _totalUsd = 0.0;
    notifyListeners();
  }

  bool isLoading = false;
  double get totalUsd => _totalUsd;
  double get totalCoins => _totalCoins;
  double withdrawableUsd = 0.0;
  double withdrawalLimit = 100.0;
  String userRole = 'consumer';
  List<dynamic> transactions = [];

  Future<bool> donateToVideo(String videoId, double amountCoin) async {
    try {
      final response = await ApiClient.post(
        '/api/v1/finance/donate',
        authenticated: true,
        body: {
          'video_id': videoId,
          'amount': amountCoin,
        },
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        _totalCoins -= amountCoin;
        if (_totalCoins < 0) _totalCoins = 0;
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Exception donating to video: $e');
      return false;
    }
  }

  Future<void> fetchDashboardStats() async {
    isLoading = true;
    notifyListeners();
    try {
      final response = await ApiClient.get('/api/v1/finance/dashboard', authenticated: true);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _totalUsd = (data['total_usd'] as num).toDouble();
        _totalCoins = (data['total_essences'] as num?)?.toDouble() ?? 0.0;
        withdrawableUsd = (data['withdrawable_usd'] as num?)?.toDouble() ?? 0.0;
        withdrawalLimit = (data['withdrawal_limit'] as num?)?.toDouble() ?? 100.0;
        userRole = data['role'] ?? 'consumer';
        transactions = data['transactions'] ?? [];
      }
    } catch (e) {
      debugPrint('Exception fetching dashboard stats: $e');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> withdrawFunds() async {
    try {
      final response = await ApiClient.post('/api/v1/finance/withdraw', authenticated: true);
      if (response.statusCode == 200 || response.statusCode == 201) {
        // Clear local state or refetch
        _totalUsd = 0.0;
        withdrawableUsd = 0.0;
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Exception withdrawing funds: $e');
      return false;
    }
  }

  Future<String?> getStripeOnboardingLink() async {
    try {
      final response = await ApiClient.post('/api/v1/stripe/onboarding', authenticated: true);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['url'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint('Exception getting stripe link: $e');
      return null;
    }
  }

  Future<bool> rechargeCoins(String productId, String purchaseToken) async {
    try {
      final response = await ApiClient.post(
        '/api/v1/finance/recharge-coins',
        authenticated: true,
        body: {
          'product_id': productId,
          'purchase_token': purchaseToken,
        },
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _totalCoins = (data['new_balance'] as num).toDouble();
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Exception recharging coins: $e');
      return false;
    }
  }

  Future<List<dynamic>> getLeaderboard() async {
    try {
      final response = await ApiClient.get('/api/v1/finance/leaderboard', authenticated: true);
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>;
      }
      return [];
    } catch (e) {
      debugPrint('Exception fetching leaderboard: $e');
      return [];
    }
  }

  Future<List<dynamic>> getPendingCustomCoins() async {
    try {
      final response = await ApiClient.get('/api/v1/finance/custom-coins/pending', authenticated: true);
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>;
      }
      return [];
    } catch (e) {
      debugPrint('Exception fetching pending custom coins: $e');
      return [];
    }
  }

  Future<bool> reviewCustomCoin(String coinId, bool isApproved) async {
    try {
      final response = await ApiClient.post(
        '/api/v1/finance/custom-coins/review',
        authenticated: true,
        body: {
          'coin_id': coinId,
          'status': isApproved ? 'approved' : 'rejected',
        },
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Exception reviewing custom coin: $e');
      return false;
    }
  }
}
