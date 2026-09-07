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
