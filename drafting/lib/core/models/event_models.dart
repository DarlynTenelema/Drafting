import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'social_platform.dart';

/// Modelo POO para un evento o transmisión en vivo.
class EventItem {
  final String id;
  final String platform;
  final String title;
  final String subtitle;
  final String actionUrl;
  final String badgeText;
  final String eventDateText;
  final String updatedAt;
  final bool isLive;
  final Map<String, dynamic> rawMap;

  const EventItem({
    required this.id,
    required this.platform,
    required this.title,
    required this.subtitle,
    required this.actionUrl,
    required this.badgeText,
    required this.eventDateText,
    required this.updatedAt,
    required this.isLive,
    required this.rawMap,
  });

  factory EventItem.fromJson(Map<String, dynamic> json) {
    return EventItem(
      id: (json['id'] ?? '').toString(),
      platform: (json['platform'] ?? 'tiktok').toString(),
      title: (json['title'] ?? '').toString(),
      subtitle: (json['subtitle'] ?? '').toString(),
      actionUrl: (json['action_url'] ?? '').toString(),
      badgeText: (json['badge_text'] ?? 'EVENTO').toString(),
      eventDateText: (json['event_date_text'] ?? '').toString(),
      updatedAt: (json['updated_at'] ?? '').toString(),
      isLive: json['is_live'] == true,
      rawMap: json,
    );
  }

  SocialPlatform get socialPlatform => SocialPlatform.fromString(platform);

  Color get accentColor => isLive ? AppTheme.hextechCrimson : socialPlatform.color;

  String get notificationDedupeKey => '$id:$updatedAt';
}

/// Modelo POO para un enlace de red social oficial de la comunidad.
class SocialLinkItem {
  final String platform;
  final String name;
  final String handle;
  final String url;

  const SocialLinkItem({
    required this.platform,
    required this.name,
    required this.handle,
    required this.url,
  });

  factory SocialLinkItem.fromJson(Map<String, dynamic> json) {
    final platformStr = (json['platform'] ?? '').toString();
    final social = SocialPlatform.fromString(platformStr);
    return SocialLinkItem(
      platform: platformStr,
      name: (json['name'] ?? social.label).toString(),
      handle: (json['handle'] ?? '').toString(),
      url: (json['url'] ?? '').toString(),
    );
  }

  SocialPlatform get socialPlatform => SocialPlatform.fromString(platform);
}
