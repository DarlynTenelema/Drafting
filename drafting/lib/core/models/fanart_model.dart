class FanartModel {
  final String id;
  final String creatorId;
  final String title;
  final String imageUrl;
  final double priceCoin;
  final String status;
  final DateTime createdAt;
  
  // Simulated UI properties based on existing design
  final String creatorName;
  final String creatorAvatar;
  final List<String> tags;
  final double aspectRatio;
  final int likes;

  FanartModel({
    required this.id,
    required this.creatorId,
    required this.title,
    required this.imageUrl,
    required this.priceCoin,
    required this.status,
    required this.createdAt,
    this.creatorName = 'Creator',
    this.creatorAvatar = 'https://i.pravatar.cc/150?img=1',
    this.tags = const [],
    this.aspectRatio = 1.0,
    this.likes = 0,
  });


  factory FanartModel.fromJson(Map<String, dynamic> json) {
    List<String> parsedTags = [];
    final rawTags = json['tags'] ?? json['Tags'];
    if (rawTags != null && rawTags.toString().isNotEmpty) {
      parsedTags = rawTags.toString().split(',').map((e) => e.trim()).toList();
    }

    return FanartModel(
      id: json['id'] ?? json['ID'] ?? '',
      creatorId: json['creator_id'] ?? json['CreatorID'] ?? '',
      title: json['title'] ?? json['Title'] ?? 'Sin Título',
      imageUrl: json['image_url'] ?? json['ImageURL'] ?? '',
      priceCoin: (json['price_coin'] ?? json['PriceCoin'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] ?? json['Status'] ?? 'approved',
      createdAt: (json['created_at'] ?? json['CreatedAt']) != null 
          ? DateTime.tryParse(json['created_at'] ?? json['CreatedAt']) ?? DateTime.now() 
          : DateTime.now(),
      tags: parsedTags,
      likes: json['likes'] ?? json['Likes'] ?? 0,
      creatorName: json['creator_name'] ?? 'Creator',
      creatorAvatar: json['creator_avatar'] ?? 'https://i.pravatar.cc/150?img=1',
    );
  }
}

