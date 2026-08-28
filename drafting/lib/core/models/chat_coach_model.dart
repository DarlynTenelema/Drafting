class MatchSession {
  final String id;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<MatchScreenshot> screenshots;
  final List<MatchChatThread> threads;

  MatchSession({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.screenshots,
    required this.threads,
  });

  factory MatchSession.fromJson(Map<String, dynamic> json) {
    return MatchSession(
      id: json['id'] ?? '',
      status: json['status'] ?? 'active',
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      screenshots: json['screenshots'] != null
          ? (json['screenshots'] as List).map((i) => MatchScreenshot.fromJson(i)).toList()
          : [],
      threads: json['threads'] != null
          ? (json['threads'] as List).map((i) => MatchChatThread.fromJson(i)).toList()
          : [],
    );
  }
}

class MatchScreenshot {
  final String id;
  final String matchSessionId;
  final String imageUrl;
  final String sceneType;
  final DateTime createdAt;

  MatchScreenshot({
    required this.id,
    required this.matchSessionId,
    required this.imageUrl,
    required this.sceneType,
    required this.createdAt,
  });

  factory MatchScreenshot.fromJson(Map<String, dynamic> json) {
    return MatchScreenshot(
      id: json['id'] ?? '',
      matchSessionId: json['match_session_id'] ?? '',
      imageUrl: json['image_url'] ?? '',
      sceneType: json['scene_type'] ?? 'draft',
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class MatchChatThread {
  final String id;
  final String matchSessionId;
  final String title;
  final DateTime createdAt;

  MatchChatThread({
    required this.id,
    required this.matchSessionId,
    required this.title,
    required this.createdAt,
  });

  factory MatchChatThread.fromJson(Map<String, dynamic> json) {
    return MatchChatThread(
      id: json['id'] ?? '',
      matchSessionId: json['match_session_id'] ?? '',
      title: json['title'] ?? 'Nuevo Chat',
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class MatchChatMessage {
  final String id;
  final String threadId;
  final String role;
  final String content;
  final DateTime createdAt;

  MatchChatMessage({
    required this.id,
    required this.threadId,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  factory MatchChatMessage.fromJson(Map<String, dynamic> json) {
    return MatchChatMessage(
      id: json['id'] ?? '',
      threadId: json['thread_id'] ?? '',
      role: json['role'] ?? 'user',
      content: json['content'] ?? '',
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}
