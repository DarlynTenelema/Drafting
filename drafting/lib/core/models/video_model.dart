class VideoModel {
  final String id;
  final String videoId;
  final String channelId;
  final String title;
  final String description;
  final List<String> tags;
  final String channelName;
  final String channelAvatar;
  final bool isChannelVerified;
  final int views;
  final DateTime createdAt;
  final int likes;
  final int commentsCount;
  final String status;

  String get viewsAndDate {
    final days = DateTime.now().difference(createdAt).inDays;
    final timeStr = days == 0 ? 'Justo ahora' : 'Hace $days días';
    return '$views vistas • $timeStr';
  }

  VideoModel({
    required this.id,
    required this.videoId,
    required this.channelId,
    required this.title,
    required this.description,
    required this.tags,
    required this.channelName,
    required this.channelAvatar,
    required this.isChannelVerified,
    required this.views,
    required this.createdAt,
    required this.likes,
    required this.commentsCount,
    required this.status,
  });

  factory VideoModel.fromJson(Map<String, dynamic> json) {
    String url = json['VideoURL'] ?? '';
    String vidId = url;
    if (url.contains('v=')) {
      vidId = url.split('v=')[1].split('&')[0];
    } else if (url.contains('youtu.be/')) {
      vidId = url.split('youtu.be/')[1].split('?')[0];
    }
    
    String tagsStr = json['Tags'] ?? '';
    List<String> parsedTags = tagsStr.isNotEmpty ? tagsStr.split(',') : [];

    return VideoModel(
      id: json['ID'] ?? '',
      channelId: json['ChannelID'] ?? '',
      videoId: vidId,
      title: json['Title'] ?? '',
      description: json['Description'] ?? '',
      tags: parsedTags,
      channelName: json['ChannelName'] ?? 'Channel Name',
      channelAvatar: json['ChannelAvatar'] ?? 'https://i.pravatar.cc/150?img=1',
      isChannelVerified: json['IsChannelVerified'] ?? false,
      views: json['Views'] ?? 0,
      createdAt: json['CreatedAt'] != null ? DateTime.parse(json['CreatedAt']) : DateTime.now(),
      likes: 0,
      commentsCount: 0,
      status: json['Status'] ?? 'pending',
    );
  }
}

class ChannelModel {
  final String? id;
  final String channelName;
  final String channelAvatar;
  final String description;
  final String bannerUrl;
  int totalViews;
  int totalSubscribers;
  final bool isVerified;

  ChannelModel({
    this.id,
    required this.channelName,
    required this.channelAvatar,
    this.description = '',
    this.bannerUrl = '',
    this.totalViews = 0,
    this.totalSubscribers = 0,
    this.isVerified = false,
  });

  factory ChannelModel.fromJson(Map<String, dynamic> json) {
    return ChannelModel(
      id: json['ID'],
      channelName: json['Name'] ?? 'Sin Nombre',
      channelAvatar: json['LogoURL'] ?? '',
      description: json['Description'] ?? '',
      bannerUrl: json['BannerURL'] ?? '',
      isVerified: json['Verified'] ?? false,
    );
  }
}
