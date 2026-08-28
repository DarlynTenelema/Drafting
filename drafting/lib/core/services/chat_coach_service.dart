import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/chat_coach_model.dart';
import 'api_client.dart';

class ChatCoachService {
  ChatCoachService._();

  static Future<List<MatchSession>> getMatches() async {
    final response = await ApiClient.get('/chat-coach/matches', authenticated: true);

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => MatchSession.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load matches: ${response.statusCode}');
    }
  }
  
  static Future<MatchChatThread> createThread(String matchId) async {
    final response = await ApiClient.post('/chat-coach/matches/$matchId/threads', authenticated: true);

    if (response.statusCode == 200 || response.statusCode == 201) {
      return MatchChatThread.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to create thread: ${response.statusCode}');
    }
  }

  static Future<List<MatchChatMessage>> getMessages(String threadId) async {
    final response = await ApiClient.get('/chat-coach/threads/$threadId/messages', authenticated: true);

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => MatchChatMessage.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load messages: ${response.statusCode}');
    }
  }

  static Future<MatchChatMessage> sendMessage(String threadId, String content) async {
    final response = await ApiClient.post(
      '/chat-coach/threads/$threadId/message',
      body: {'content': content},
      authenticated: true,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return MatchChatMessage.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to send message: ${response.statusCode}');
    }
  }

  static Future<MatchChatMessage> sendVideoMessage(String threadId, String content, String videoPath) async {
    final response = await ApiClient.multipartPost(
      '/chat-coach/threads/$threadId/video-message',
      fields: {'content': content},
      fileField: 'video',
      filePath: videoPath,
      authenticated: true,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return MatchChatMessage.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to send video message: ${response.statusCode}');
    }
  }
}
