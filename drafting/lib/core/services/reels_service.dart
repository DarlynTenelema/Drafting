import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'api_client.dart';
import 'session_service.dart';

class ReelModel {
  final String id;
  final String creatorId;
  final String title;
  final String description;
  final String videoUrl;
  final String thumbnailUrl;
  final int durationSeconds;
  final int width;
  final int height;
  final String orientation;
  final String gameMode;
  final String category;
  final String language;
  final String championName;
  final int likesCount;
  final int commentsCount;
  final int savesCount;
  final int viewsCount;
  final int verifiedViewsCount;
  final double trendScore;
  final String creatorUsername;
  final String creatorAvatar;
  final int creatorFollowersCount;
  final String moderationStatus;
  bool hasLiked;
  bool hasSaved;
  bool isFollowing;
  int currentLikes;
  int currentComments;
  int currentSaves;
  int currentFollowers;

  ReelModel({
    required this.id,
    required this.creatorId,
    required this.title,
    required this.description,
    required this.videoUrl,
    required this.thumbnailUrl,
    required this.durationSeconds,
    this.width = 0,
    this.height = 0,
    this.orientation = 'portrait',
    required this.gameMode,
    required this.category,
    required this.language,
    required this.championName,
    required this.likesCount,
    required this.commentsCount,
    required this.savesCount,
    required this.viewsCount,
    this.verifiedViewsCount = 0,
    required this.trendScore,
    required this.creatorUsername,
    required this.creatorAvatar,
    this.creatorFollowersCount = 0,
    this.moderationStatus = 'approved',
    this.hasLiked = false,
    this.hasSaved = false,
    this.isFollowing = false,
  })  : currentLikes = likesCount,
        currentComments = commentsCount,
        currentSaves = savesCount,
        currentFollowers = creatorFollowersCount;

  factory ReelModel.fromJson(Map<String, dynamic> json) {
    return ReelModel(
      id: json['id']?.toString() ?? '',
      creatorId: json['creator_id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      videoUrl: json['video_url']?.toString() ?? '',
      thumbnailUrl: json['thumbnail_url']?.toString() ?? '',
      durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 15,
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      orientation: json['orientation']?.toString() ?? 'portrait',
      gameMode: json['game_mode']?.toString() ?? 'wild_rift',
      category: json['category']?.toString() ?? 'jugadas',
      language: json['language']?.toString() ?? 'universal',
      championName: json['champion_name']?.toString() ?? '',
      likesCount: (json['likes_count'] as num?)?.toInt() ?? 0,
      commentsCount: (json['comments_count'] as num?)?.toInt() ?? 0,
      savesCount: (json['saves_count'] as num?)?.toInt() ?? 0,
      viewsCount: (json['views_count'] as num?)?.toInt() ?? 0,
      verifiedViewsCount: (json['verified_views_count'] as num?)?.toInt() ?? 0,
      trendScore: (json['trend_score'] as num?)?.toDouble() ?? 0.0,
      creatorUsername: json['creator_username']?.toString() ?? 'Invocador',
      creatorAvatar: json['creator_avatar']?.toString() ?? '',
      creatorFollowersCount: (json['creator_followers_count'] as num?)?.toInt() ?? 0,
      moderationStatus: json['moderation_status']?.toString() ?? 'approved',
      hasLiked: json['has_liked'] == true,
      hasSaved: json['has_saved'] == true,
      isFollowing: json['is_following'] == true,
    );
  }

  bool get isLandscape {
    if (width > 0 && height > 0) {
      return width > height * 1.05;
    }
    return orientation.toLowerCase() == 'landscape';
  }
}

class ReelCommentModel {
  final String id;
  final String reelId;
  final String userId;
  final String username;
  final String profilePic;
  final String content;
  final DateTime createdAt;

  ReelCommentModel({
    required this.id,
    required this.reelId,
    required this.userId,
    required this.username,
    required this.profilePic,
    required this.content,
    required this.createdAt,
  });

  factory ReelCommentModel.fromJson(Map<String, dynamic> json) {
    DateTime parsedDate;
    try {
      parsedDate = DateTime.parse(json['created_at'].toString());
    } catch (_) {
      parsedDate = DateTime.now();
    }

    return ReelCommentModel(
      id: json['id']?.toString() ?? '',
      reelId: json['reel_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      username: json['username']?.toString() ?? 'Invocador',
      profilePic: json['profile_pic']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      createdAt: parsedDate,
    );
  }
}

class UserReelsStats {
  final int totalReels;
  final int totalViews;
  final int totalVerifiedViews;
  final int lifetimeVerifiedViews;
  final int totalLikes;
  final int totalComments;
  final int totalSaves;
  final int followersCount;
  final int followingCount;
  final double estimatedEarningsUsd;
  final double pendingPayoutUsd;
  final double paidOutUsd;
  final double availableBalanceUsd;
  final double minPayoutUsd;
  final bool canWithdraw;

  UserReelsStats({
    required this.totalReels,
    required this.totalViews,
    this.totalVerifiedViews = 0,
    this.lifetimeVerifiedViews = 0,
    required this.totalLikes,
    required this.totalComments,
    required this.totalSaves,
    this.followersCount = 0,
    this.followingCount = 0,
    this.estimatedEarningsUsd = 0.0,
    this.pendingPayoutUsd = 0.0,
    this.paidOutUsd = 0.0,
    this.availableBalanceUsd = 0.0,
    this.minPayoutUsd = 100.0,
    this.canWithdraw = false,
  });

  factory UserReelsStats.fromJson(Map<String, dynamic> json) {
    final est = (json['estimated_earnings_usd'] as num?)?.toDouble() ?? 0.0;
    return UserReelsStats(
      totalReels: (json['total_reels'] as num?)?.toInt() ?? 0,
      totalViews: (json['total_views'] as num?)?.toInt() ?? 0,
      totalVerifiedViews: (json['total_verified_views'] as num?)?.toInt() ?? 0,
      lifetimeVerifiedViews: (json['lifetime_verified_views'] as num?)?.toInt() ??
          (json['total_verified_views'] as num?)?.toInt() ??
          0,
      totalLikes: (json['total_likes'] as num?)?.toInt() ?? 0,
      totalComments: (json['total_comments'] as num?)?.toInt() ?? 0,
      totalSaves: (json['total_saves'] as num?)?.toInt() ?? 0,
      followersCount: (json['followers_count'] as num?)?.toInt() ?? 0,
      followingCount: (json['following_count'] as num?)?.toInt() ?? 0,
      estimatedEarningsUsd: est,
      pendingPayoutUsd: (json['pending_payout_usd'] as num?)?.toDouble() ?? 0.0,
      paidOutUsd: (json['paid_out_usd'] as num?)?.toDouble() ?? 0.0,
      availableBalanceUsd: (json['available_balance_usd'] as num?)?.toDouble() ?? est,
      minPayoutUsd: (json['min_payout_usd'] as num?)?.toDouble() ?? 100.0,
      canWithdraw: json['can_withdraw'] == true,
    );
  }
}

class CreatorSocialProfile {
  final String id;
  final String username;
  final String profilePic;
  final String bio;
  final String twitchUrl;
  final String tiktokUrl;
  final String youtubeUrl;
  final String instagramUrl;
  final String kickUrl;
  final bool isFollowing;

  const CreatorSocialProfile({
    this.id = '',
    this.username = 'Invocador',
    this.profilePic = '',
    this.bio = '',
    this.twitchUrl = '',
    this.tiktokUrl = '',
    this.youtubeUrl = '',
    this.instagramUrl = '',
    this.kickUrl = '',
    this.isFollowing = false,
  });

  factory CreatorSocialProfile.fromJson(Map<String, dynamic> json) {
    return CreatorSocialProfile(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? 'Invocador',
      profilePic: json['profile_pic']?.toString() ?? '',
      bio: json['bio']?.toString() ?? '',
      twitchUrl: json['twitch_url']?.toString() ?? '',
      tiktokUrl: json['tiktok_url']?.toString() ?? '',
      youtubeUrl: json['youtube_url']?.toString() ?? '',
      instagramUrl: json['instagram_url']?.toString() ?? '',
      kickUrl: json['kick_url']?.toString() ?? '',
      isFollowing: json['is_following'] == true,
    );
  }

  bool get hasAnySocialLink =>
      twitchUrl.isNotEmpty ||
      tiktokUrl.isNotEmpty ||
      youtubeUrl.isNotEmpty ||
      instagramUrl.isNotEmpty ||
      kickUrl.isNotEmpty;
}

class CreatorPayoutModel {
  final String id;
  final double amountUsd;
  final int verifiedViewsSnapshot;
  final String payoutMethod;
  final String payoutDestination;
  final String status;
  final String adminNotes;
  final DateTime createdAt;

  const CreatorPayoutModel({
    required this.id,
    required this.amountUsd,
    required this.verifiedViewsSnapshot,
    required this.payoutMethod,
    required this.payoutDestination,
    required this.status,
    required this.adminNotes,
    required this.createdAt,
  });

  factory CreatorPayoutModel.fromJson(Map<String, dynamic> json) {
    DateTime created;
    try {
      created = DateTime.parse(json['created_at'].toString());
    } catch (_) {
      created = DateTime.now();
    }
    return CreatorPayoutModel(
      id: json['id']?.toString() ?? '',
      amountUsd: (json['amount_usd'] as num?)?.toDouble() ?? 0.0,
      verifiedViewsSnapshot: (json['verified_views_snapshot'] as num?)?.toInt() ?? 0,
      payoutMethod: json['payout_method']?.toString() ?? 'paypal',
      payoutDestination: json['payout_destination']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      adminNotes: json['admin_notes']?.toString() ?? '',
      createdAt: created,
    );
  }
}

class ReelsFeedPage {
  final List<ReelModel> reels;
  final String? nextCursor;

  const ReelsFeedPage({
    required this.reels,
    this.nextCursor,
  });
}

class CreatorReelsProfile {
  final String id;
  final String username;
  final String profilePic;
  final CreatorSocialProfile social;
  final UserReelsStats? stats;
  final List<ReelModel> reels;

  const CreatorReelsProfile({
    required this.id,
    required this.username,
    required this.profilePic,
    this.social = const CreatorSocialProfile(),
    this.stats,
    required this.reels,
  });
}

class ReelsService {
  ReelsService._();

  static String _extractError(http.Response resp, String fallback) {
    try {
      final data = jsonDecode(resp.body);
      if (data is Map && data['error'] != null && data['error'].toString().isNotEmpty) {
        return data['error'].toString();
      }
    } catch (_) {}
    return fallback;
  }

  static Future<ReelsFeedPage> getFeedPage({
    String? lang,
    String? category,
    String? gameMode,
    String? cursor,
    int limit = 10,
  }) async {
    final queryParams = <String, String>{
      'limit': limit.toString(),
      if (lang != null && lang.isNotEmpty) 'lang': lang,
      if (category != null && category.isNotEmpty) 'category': category,
      if (gameMode != null && gameMode.isNotEmpty) 'game_mode': gameMode,
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };

    final uri = AppConfig.apiUri('/reels/feed').replace(queryParameters: queryParams);
    final token = await SessionService.getSessionToken();
    final headers = <String, String>{
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };

    final resp = await http.get(uri, headers: headers);
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final list = (data['reels'] as List?) ?? [];
      final rawCursor = data['next_cursor']?.toString();
      return ReelsFeedPage(
        reels: list.map((item) => ReelModel.fromJson(item as Map<String, dynamic>)).toList(),
        nextCursor: (rawCursor != null && rawCursor.isNotEmpty) ? rawCursor : null,
      );
    }
    throw ApiException(_extractError(resp, 'Error al cargar el feed'));
  }

  static Future<List<ReelModel>> getFeed({
    String? lang,
    String? category,
    String? gameMode,
    String? cursor,
    int limit = 10,
  }) async {
    final page = await getFeedPage(
      lang: lang,
      category: category,
      gameMode: gameMode,
      cursor: cursor,
      limit: limit,
    );
    return page.reels;
  }

  static Future<CreatorReelsProfile?> getUserProfile(String userId) async {
    final token = await SessionService.getSessionToken();
    final headers = <String, String>{
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    final resp = await http.get(AppConfig.apiUri('/reels/users/$userId'), headers: headers);
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final userMap = (data['user'] as Map<String, dynamic>?) ?? {};
      final list = (data['reels'] as List?) ?? [];
      final stats = data['stats'] is Map<String, dynamic>
          ? UserReelsStats.fromJson(data['stats'] as Map<String, dynamic>)
          : null;
      final social = CreatorSocialProfile.fromJson(userMap);
      return CreatorReelsProfile(
        id: social.id.isNotEmpty ? social.id : userId,
        username: social.username,
        profilePic: social.profilePic,
        social: social,
        stats: stats,
        reels: list.map((item) => ReelModel.fromJson(item as Map<String, dynamic>)).toList(),
      );
    }
    return null;
  }

  static Future<Map<String, dynamic>> toggleFollow(String userId) async {
    final resp = await ApiClient.post('/reels/users/$userId/follow', authenticated: true);
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    throw ApiException(_extractError(resp, 'No se pudo actualizar el seguimiento'));
  }

  static Future<CreatorSocialProfile> updateCreatorProfile({
    String? bio,
    String? twitchUrl,
    String? tiktokUrl,
    String? youtubeUrl,
    String? instagramUrl,
    String? kickUrl,
  }) async {
    final body = <String, dynamic>{};
    if (bio != null) body['bio'] = bio;
    if (twitchUrl != null) body['twitch_url'] = twitchUrl;
    if (tiktokUrl != null) body['tiktok_url'] = tiktokUrl;
    if (youtubeUrl != null) body['youtube_url'] = youtubeUrl;
    if (instagramUrl != null) body['instagram_url'] = instagramUrl;
    if (kickUrl != null) body['kick_url'] = kickUrl;

    final resp = await ApiClient.put('/auth/me', authenticated: true, body: body);
    if (resp.statusCode == 200) {
      return CreatorSocialProfile.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
    }
    throw ApiException(_extractError(resp, 'No se pudo actualizar tu perfil'));
  }

  static Future<List<CreatorPayoutModel>> getMyPayouts() async {
    final resp = await ApiClient.get('/reels/me/payouts', authenticated: true);
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final list = (data['payouts'] as List?) ?? [];
      return list.map((item) => CreatorPayoutModel.fromJson(item as Map<String, dynamic>)).toList();
    }
    return [];
  }

  static Future<String> requestPayout({
    required String payoutMethod,
    required String payoutDestination,
  }) async {
    final resp = await ApiClient.post(
      '/reels/me/payouts',
      authenticated: true,
      body: {
        'payout_method': payoutMethod,
        'payout_destination': payoutDestination,
      },
    );
    if (resp.statusCode == 201 || resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return data['message']?.toString() ?? 'Solicitud de retiro enviada';
    }
    throw ApiException(_extractError(resp, 'No se pudo solicitar el retiro'));
  }

  static Future<Map<String, dynamic>> toggleLike(String reelId) async {
    final resp = await ApiClient.post('/reels/$reelId/like', authenticated: true);
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    throw ApiException(_extractError(resp, 'No se pudo procesar el me gusta'));
  }

  static Future<Map<String, dynamic>> toggleSave(String reelId) async {
    final resp = await ApiClient.post('/reels/$reelId/save', authenticated: true);
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    throw ApiException(_extractError(resp, 'No se pudo guardar el video'));
  }

  /// Inicia una sesión de reproducción y devuelve el token firmado anti-bot del servidor.
  static Future<String?> startViewSession(String reelId) async {
    try {
      final token = await SessionService.getSessionToken();
      final headers = <String, String>{
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };
      final resp = await http.post(AppConfig.apiUri('/reels/$reelId/view/start'), headers: headers);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        return data['view_token']?.toString();
      }
    } catch (_) {}
    return null;
  }

  /// Registra una vista única (verificada si alcanzó >=90% del video con token firmado válido).
  static Future<void> recordView(
    String reelId, {
    String? viewToken,
    int watchedSeconds = 0,
    int watchedPercent = 0,
  }) async {
    try {
      final token = await SessionService.getSessionToken();
      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };
      await http.post(
        AppConfig.apiUri('/reels/$reelId/view'),
        headers: headers,
        body: jsonEncode({
          'view_token': viewToken ?? '',
          'watched_seconds': watchedSeconds,
          'watched_percent': watchedPercent,
        }),
      );
    } catch (_) {}
  }

  /// Reporta un reel por contenido inapropiado o baja calidad.
  static Future<String> reportReel(
    String reelId, {
    required String reason,
    String details = '',
  }) async {
    final resp = await ApiClient.post(
      '/reels/$reelId/report',
      authenticated: true,
      body: {
        'reason': reason,
        'details': details,
      },
    );
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      return data['message']?.toString() ?? 'Reporte enviado';
    }
    throw ApiException(_extractError(resp, 'No se pudo enviar el reporte'));
  }

  /// Bloquea o desbloquea a un creador para ocultar inmediatamente todos sus videos y comentarios (Play Store UGC).
  static Future<Map<String, dynamic>> toggleBlockUser(String userId) async {
    final resp = await ApiClient.post(
      '/reels/users/$userId/block',
      authenticated: true,
    );
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    throw ApiException(_extractError(resp, 'No se pudo bloquear al usuario'));
  }

  static Future<List<ReelCommentModel>> getComments(String reelId) async {
    final resp = await ApiClient.get('/reels/$reelId/comments');
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      final list = (data['comments'] as List?) ?? [];
      return list.map((item) => ReelCommentModel.fromJson(item as Map<String, dynamic>)).toList();
    }
    return [];
  }

  static Future<ReelCommentModel> addComment(String reelId, String content) async {
    final resp = await ApiClient.post(
      '/reels/$reelId/comments',
      authenticated: true,
      body: {'content': content},
    );
    if (resp.statusCode == 201) {
      return ReelCommentModel.fromJson(jsonDecode(resp.body));
    }
    throw ApiException(_extractError(resp, 'Error al publicar comentario'));
  }

  static Future<void> deleteComment(String commentId) async {
    final resp = await ApiClient.delete('/reels/comments/$commentId', authenticated: true);
    if (resp.statusCode != 200) {
      throw ApiException(_extractError(resp, 'No se pudo eliminar el comentario'));
    }
  }

  /// Sube el video comprimido a 720p usando URL prefirmada directa a R2/S3 (cero RAM en el servidor Go)
  /// con fallback automático a multipart si el backend está en modo almacenamiento local.
  static Future<Map<String, dynamic>> uploadMedia({
    required File videoFile,
    File? thumbnailFile,
    required int durationSeconds,
  }) async {
    final fileSizeBytes = await videoFile.length();
    final filename = videoFile.path.split(Platform.pathSeparator).last;

    // 1. Solicitar URL prefirmada y validar límite diario (2/día) y tamaño (<=15MB) antes de transferir bytes
    final presignResp = await ApiClient.post(
      '/reels/presign-upload',
      authenticated: true,
      body: {
        'filename': filename,
        'content_type': 'video/mp4',
        'file_size_bytes': fileSizeBytes,
        'duration_seconds': durationSeconds,
        'include_thumb': thumbnailFile != null,
      },
    );

    if (presignResp.statusCode != 200) {
      throw ApiException(_extractError(presignResp, 'No se pudo autorizar la subida del video'));
    }

    final presignData = jsonDecode(presignResp.body) as Map<String, dynamic>;
    if (presignData['use_direct_upload'] == true && presignData['video'] is Map) {
      final videoInfo = presignData['video'] as Map<String, dynamic>;
      final uploadUrl = videoInfo['upload_url']?.toString() ?? '';
      final videoKey = videoInfo['object_key']?.toString() ?? '';
      final publicUrl = videoInfo['public_url']?.toString() ?? '';

      final videoBytes = await videoFile.readAsBytes();
      final putResp = await http.put(
        Uri.parse(uploadUrl),
        headers: {'Content-Type': 'video/mp4'},
        body: videoBytes,
      );
      if (putResp.statusCode < 200 || putResp.statusCode >= 300) {
        throw ApiException('Error subiendo el video al almacenamiento (${putResp.statusCode})');
      }

      String thumbPublicUrl = '';
      if (thumbnailFile != null && presignData['thumbnail'] is Map) {
        final thumbInfo = presignData['thumbnail'] as Map<String, dynamic>;
        final thumbUploadUrl = thumbInfo['upload_url']?.toString() ?? '';
        if (thumbUploadUrl.isNotEmpty) {
          final thumbBytes = await thumbnailFile.readAsBytes();
          final thumbPut = await http.put(
            Uri.parse(thumbUploadUrl),
            headers: {'Content-Type': 'image/jpeg'},
            body: thumbBytes,
          );
          if (thumbPut.statusCode >= 200 && thumbPut.statusCode < 300) {
            thumbPublicUrl = thumbInfo['public_url']?.toString() ?? '';
          }
        }
      }

      return {
        'video_url': publicUrl,
        'video_key': videoKey,
        'thumbnail_url': thumbPublicUrl,
        'file_size_bytes': fileSizeBytes,
      };
    }

    // 2. Fallback multipart para desarrollo local sin R2/S3
    final token = await SessionService.getSessionToken();
    final request = http.MultipartRequest('POST', AppConfig.apiUri('/reels/upload'));

    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    request.files.add(await http.MultipartFile.fromPath('video', videoFile.path));
    if (thumbnailFile != null) {
      request.files.add(await http.MultipartFile.fromPath('thumbnail', thumbnailFile.path));
    }

    final streamedResp = await request.send();
    final resp = await http.Response.fromStream(streamedResp);

    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return {
        'video_url': data['video_url']?.toString() ?? '',
        'video_key': data['video_key']?.toString() ?? '',
        'thumbnail_url': data['thumbnail_url']?.toString() ?? '',
        'file_size_bytes': (data['file_size_bytes'] as num?)?.toInt() ?? fileSizeBytes,
      };
    }
    throw ApiException(_extractError(resp, 'Error al subir archivos multimedia'));
  }

  static Future<ReelModel> createReel(Map<String, dynamic> data) async {
    final resp = await ApiClient.post('/reels', authenticated: true, body: data);
    if (resp.statusCode == 201) {
      return ReelModel.fromJson(jsonDecode(resp.body));
    }
    throw ApiException(_extractError(resp, 'Error al publicar el reel'));
  }

  static Future<Map<String, dynamic>> getMyUploadedReels() async {
    final resp = await ApiClient.get('/reels/me/uploaded', authenticated: true);
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      final list = (data['reels'] as List?) ?? [];
      final stats = data['stats'] != null ? UserReelsStats.fromJson(data['stats']) : null;
      final user = data['user'] is Map<String, dynamic>
          ? CreatorSocialProfile.fromJson(data['user'] as Map<String, dynamic>)
          : null;
      return {
        'user': user,
        'stats': stats,
        'reels': list.map((item) => ReelModel.fromJson(item as Map<String, dynamic>)).toList(),
      };
    }
    return {'user': null, 'stats': null, 'reels': <ReelModel>[]};
  }

  static Future<List<ReelModel>> getMyLikedReels() async {
    final resp = await ApiClient.get('/reels/me/liked', authenticated: true);
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      final list = (data['reels'] as List?) ?? [];
      return list.map((item) => ReelModel.fromJson(item as Map<String, dynamic>)).toList();
    }
    return [];
  }

  static Future<List<ReelModel>> getMySavedReels() async {
    final resp = await ApiClient.get('/reels/me/saved', authenticated: true);
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      final list = (data['reels'] as List?) ?? [];
      return list.map((item) => ReelModel.fromJson(item as Map<String, dynamic>)).toList();
    }
    return [];
  }

  static Future<void> deleteReel(String reelId) async {
    final resp = await ApiClient.delete('/reels/$reelId', authenticated: true);
    if (resp.statusCode != 200) {
      throw ApiException(_extractError(resp, 'Error al eliminar el video'));
    }
  }
}
