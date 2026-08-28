import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'api_client.dart';

class CommentModel {
  final String id;
  final String videoId;
  final String userId;
  final String? parentId;
  final String content;
  final int likes;
  final DateTime createdAt;
  
  // Author info
  final String authorName;
  final String authorAvatar;

  CommentModel({
    required this.id,
    required this.videoId,
    required this.userId,
    this.parentId,
    required this.content,
    required this.likes,
    required this.createdAt,
    required this.authorName,
    required this.authorAvatar,
  });

  factory CommentModel.fromJson(Map<String, dynamic> json) {
    final user = json['User'] ?? {};
    return CommentModel(
      id: json['ID'] ?? '',
      videoId: json['VideoID'] ?? '',
      userId: json['UserID'] ?? '',
      parentId: json['ParentID'],
      content: json['Content'] ?? '',
      likes: json['Likes'] ?? 0,
      createdAt: json['CreatedAt'] != null ? DateTime.parse(json['CreatedAt']) : DateTime.now(),
      authorName: user['Username'] ?? 'Usuario',
      authorAvatar: user['ProfilePic'] ?? 'https://i.pravatar.cc/150?u=${json['UserID']}',
    );
  }
}

class InteractionService extends ChangeNotifier {
  static final InteractionService _instance = InteractionService._internal();
  factory InteractionService() => _instance;
  InteractionService._internal();

  List<CommentModel> _comments = [];
  bool isLoadingComments = false;

  List<CommentModel> get topLevelComments => _comments.where((c) => c.parentId == null).toList();

  List<CommentModel> getReplies(String parentId) {
    return _comments.where((c) => c.parentId == parentId).toList();
  }

  Future<void> fetchComments(String contentId, {String contentType = 'video'}) async {
    isLoadingComments = true;
    notifyListeners();
    try {
      final response = await ApiClient.get('/interaction/comments?content_id=$contentId&content_type=$contentType', authenticated: true);
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        _comments = data.map((json) => CommentModel.fromJson(json)).toList();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Exception fetching comments: $e');
    } finally {
      isLoadingComments = false;
      notifyListeners();
    }
  }

  Future<bool> postComment(String contentId, String content, {String? parentId, String contentType = 'video'}) async {
    try {
      final response = await ApiClient.post(
        '/interaction/comment',
        authenticated: true,
        body: {
          'content_id': contentId,
          'content_type': contentType,
          'content': content,
          'parent_id': parentId,
        },
      );
      if (response.statusCode == 201) {
        final newComment = CommentModel.fromJson(jsonDecode(response.body));
        _comments.add(newComment);
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> updateComment(String commentId, String content) async {
    try {
      final response = await ApiClient.put(
        '/interaction/comment',
        authenticated: true,
        body: {
          'comment_id': commentId,
          'content': content,
        },
      );
      if (response.statusCode == 200) {
        final updatedComment = CommentModel.fromJson(jsonDecode(response.body));
        final index = _comments.indexWhere((c) => c.id == commentId);
        if (index != -1) {
          _comments[index] = updatedComment;
          notifyListeners();
        }
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteComment(String commentId) async {
    try {
      final response = await ApiClient.delete(
        '/interaction/comment?comment_id=$commentId',
        authenticated: true,
      );
      if (response.statusCode == 200) {
        _comments.removeWhere((c) => c.id == commentId);
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>> toggleVideoLike(String videoId) async {
    try {
      final response = await ApiClient.post(
        '/interaction/like',
        authenticated: true,
        body: {'video_id': videoId},
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return {'is_liked': false, 'total_likes': 0};
    } catch (e) {
      return {'is_liked': false, 'total_likes': 0};
    }
  }

  Future<void> incrementView(String videoId) async {
    try {
      await ApiClient.post(
        '/interaction/view',
        authenticated: false,
        body: {'video_id': videoId},
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Error incrementing view: $e');
    }
  }

  Future<Map<String, dynamic>> toggleSubscription(String channelId, {bool notify = false}) async {
    try {
      final response = await ApiClient.post(
        '/interaction/subscribe',
        authenticated: true,
        body: {'channel_id': channelId, 'notify': notify},
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error toggling sub: $e');
    }
    return {'is_subscribed': false, 'notifications_enabled': false, 'total_subscribers': 0};
  }

  Future<Map<String, dynamic>> getSubscriptionStatus(String channelId) async {
    try {
      final response = await ApiClient.get(
        '/interaction/subscription_status?channel_id=$channelId',
        authenticated: true, // using true so we know if CURRENT user is subbed
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error getting sub status: $e');
    }
    return {'is_subscribed': false, 'notifications_enabled': false, 'total_subscribers': 0};
  }
}

