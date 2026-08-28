import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/video_model.dart';
import 'api_client.dart';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

class VideoService extends ChangeNotifier {
  static final VideoService _instance = VideoService._internal();
  factory VideoService() => _instance;
  VideoService._internal();

  ChannelModel? currentUserChannel;

  List<VideoModel> _videos = [];
  bool isLoading = false;

  List<VideoModel> get videos => _videos;

  Future<String?> createChannel(String name, String avatarPath) async {
    isLoading = true;
    notifyListeners();
    try {
      String finalAvatarUrl = avatarPath;
      
      if (!avatarPath.startsWith('http')) {
        final file = File(avatarPath);
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_avatar.jpg';
        await Supabase.instance.client.storage.from('avatars').upload(fileName, file);
        finalAvatarUrl = Supabase.instance.client.storage.from('avatars').getPublicUrl(fileName);
      }

      final response = await ApiClient.post(
        '/content/channel', 
        authenticated: true,
        body: {
          'name': name,
          'logo_url': finalAvatarUrl,
        }
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        currentUserChannel = ChannelModel.fromJson(data);
        return null; // Success
      } else {
        debugPrint('Error creating channel: ${response.statusCode} - ${response.body}');
        return 'Error ${response.statusCode}: ${response.body}';
      }
    } catch (e) {
      debugPrint('Exception creating channel: $e');
      return 'Exception: $e';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchVideos() async {
    isLoading = true;
    notifyListeners();
    try {
      final response = await ApiClient.get('/content/approved?type=videos', authenticated: true);
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        _videos = data.map((json) => VideoModel.fromJson(json)).toList();
      } else {
        debugPrint('Error fetching videos: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Exception fetching videos: $e');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<List<VideoModel>> searchVideos(String query) async {
    try {
      final response = await ApiClient.get('/content/approved?type=videos&q=${Uri.encodeQueryComponent(query)}', authenticated: true);
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => VideoModel.fromJson(json)).toList();
      } else {
        debugPrint('Error searching videos: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('Exception searching videos: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> addVideo(VideoModel video, String channelId) async {
    try {
      final response = await ApiClient.post(
        '/content/video',
        authenticated: true,
        body: {
          'channel_id': channelId,
          'title': video.title,
          'description': video.description,
          'video_url': 'https://youtube.com/watch?v=${video.videoId}',
          'tags': video.tags.join(','),
        },
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final status = data['Status'] ?? 'approved';
        if (status == 'approved') {
          _videos.insert(0, video);
          notifyListeners();
        }
        return {'success': true, 'status': status, 'message': 'Success'};
      } else if (response.statusCode == 409) {
        return {'success': false, 'message': 'Este video ya ha sido subido a la plataforma por otro creador.'};
      } else {
        return {'success': false, 'message': 'Error del servidor: ${response.statusCode}'};
      }
    } catch (e) {
      debugPrint('Exception adding video: $e');
      return {'success': false, 'message': 'Error de conexión: $e'};
    }
  }

  Future<void> fetchMyChannel() async {
    try {
      final response = await ApiClient.get('/content/channel/me', authenticated: true);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['channel'] != null) {
          currentUserChannel = ChannelModel.fromJson(data['channel']);
          currentUserChannel!.totalViews = data['total_views'] ?? 0;
          currentUserChannel!.totalSubscribers = data['total_subscribers'] ?? 0;
        } else {
          currentUserChannel = ChannelModel.fromJson(data);
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Exception fetching my channel: $e');
    }
  }

  Future<bool> updateChannel(ChannelModel channel) async {
    try {
      final response = await ApiClient.put(
        '/content/channel',
        authenticated: true,
        body: {
          'name': channel.channelName,
          'description': channel.description,
          'logo_url': channel.channelAvatar,
          'banner_url': channel.bannerUrl,
        },
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        currentUserChannel = channel;
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<List<VideoModel>> fetchMyVideos() async {
    try {
      final response = await ApiClient.get('/content/video/me', authenticated: true);
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => VideoModel.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<bool> updateVideo(VideoModel video) async {
    try {
      final response = await ApiClient.put(
        '/content/video',
        authenticated: true,
        body: {
          'video_id': video.id,
          'title': video.title,
          'description': video.description,
          'tags': video.tags.join(','),
        },
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        // Optimistically update the list if it's there
        final index = _videos.indexWhere((v) => v.id == video.id);
        if (index != -1) {
          _videos[index] = video;
          notifyListeners();
        }
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteVideo(String videoId) async {
    try {
      final response = await ApiClient.delete(
        '/content/video?id=$videoId',
        authenticated: true,
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        _videos.removeWhere((v) => v.id == videoId);
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}

