import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/services/session_service.dart';
import '../theme/app_theme.dart';
import '../core/utils/text_validator.dart';
import '../core/config/app_config.dart';

class TicketChatScreen extends StatefulWidget {
  final Map<String, dynamic> ticket;

  const TicketChatScreen({super.key, required this.ticket});

  @override
  State<TicketChatScreen> createState() => _TicketChatScreenState();
}

class _TicketChatScreenState extends State<TicketChatScreen> {
  List<dynamic> _messages = [];
  bool _isLoading = true;
  final _replyController = TextEditingController();
  bool _isSending = false;
  String? _myUserId;

  @override
  void initState() {
    super.initState();
    _fetchMessages();
  }

  Future<void> _fetchMessages() async {
    setState(() => _isLoading = true);
    try {
      final token = await SessionService.getSessionToken();
      
      // Get user ID first
      if (_myUserId == null) {
        final meResponse = await http.get(
          AppConfig.apiUri('/api/v1/auth/me'),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (meResponse.statusCode == 200) {
          final data = json.decode(meResponse.body);
          _myUserId = data['id'];
        }
      }
      
      final response = await http.get(
        AppConfig.apiUri('/api/v1/support/tickets/${widget.ticket['id']}/messages'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        setState(() {
          _messages = json.decode(response.body);
        });
      }
    } catch (e) {
      debugPrint('Error fetching messages: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;
    
    if (TextValidator.hasHiddenAbbreviations(text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Tu mensaje contiene siglas o palabras sin vocales. Por favor escribe las palabras completas.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isSending = true);
    try {
      final token = await SessionService.getSessionToken();
      final body = json.encode({"message": _replyController.text.trim()});

      final response = await http.post(
        AppConfig.apiUri('/api/v1/support/tickets/${widget.ticket['id']}/reply'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json'
        },
        body: body,
      );

      if (response.statusCode == 201) {
        _replyController.clear();
        _fetchMessages(); // Recargar mensajes
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text('Reporte #${widget.ticket['id'].toString().substring(0,6)}', style: GoogleFonts.outfit(fontSize: 16)),
        backgroundColor: AppTheme.surface,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Info del Ticket en el tope
          Container(
            padding: const EdgeInsets.all(16),
            color: AppTheme.surface,
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.ticket['subject'], style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(4)),
                      child: Text(widget.ticket['ticket_type'].toString().toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 10)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(4)),
                      child: Text('Prioridad: ${widget.ticket['priority']}', style: const TextStyle(color: Colors.white70, fontSize: 10)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isMe = msg['sender_id'] == _myUserId;
                      
                      return Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(12),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                          decoration: BoxDecoration(
                            color: isMe ? AppTheme.accent : AppTheme.surface,
                            borderRadius: BorderRadius.circular(12).copyWith(
                              bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(12),
                              bottomLeft: !isMe ? const Radius.circular(0) : const Radius.circular(12),
                            ),
                          ),
                          child: Text(
                            msg['message'],
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          
          // Input Box
          Container(
            padding: const EdgeInsets.all(16),
            color: AppTheme.surface,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _replyController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Escribe tu respuesta...',
                      hintStyle: const TextStyle(color: Colors.white30),
                      filled: true,
                      fillColor: AppTheme.background,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: const BoxDecoration(color: AppTheme.accent, shape: BoxShape.circle),
                  child: IconButton(
                    icon: _isSending ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: _isSending ? null : _sendReply,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
