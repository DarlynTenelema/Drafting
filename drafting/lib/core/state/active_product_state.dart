import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ActiveProductState {
  static final ActiveProductState _instance = ActiveProductState._internal();
  factory ActiveProductState() => _instance;
  ActiveProductState._internal();

  final ValueNotifier<String?> activeProductNotifier = ValueNotifier<String?>(null);
  final ValueNotifier<String?> activeCreatorIdNotifier = ValueNotifier<String?>(null);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    activeProductNotifier.value = prefs.getString('active_product');
  }

  Future<void> setActiveProduct(String productName, String creatorId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_product', productName);
    await prefs.setString('active_creator_id', creatorId);
    
    activeProductNotifier.value = productName;
    activeCreatorIdNotifier.value = creatorId;
  }

  Future<void> clearActiveProduct() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('active_product');
    await prefs.remove('active_creator_id');
    
    activeProductNotifier.value = null;
    activeCreatorIdNotifier.value = null;
  }
}
