import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:math';
import '../theme/app_theme.dart';

import '../core/models/chat_coach_model.dart';
import '../core/services/chat_coach_service.dart';
import 'chat_coach_prompts_screen.dart';

class ChatCoachScreen extends StatefulWidget {
  final Widget? bottomNavBar;

  const ChatCoachScreen({super.key, this.bottomNavBar});

  @override
  State<ChatCoachScreen> createState() => _ChatCoachScreenState();
}

class _ChatCoachScreenState extends State<ChatCoachScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  bool _isSending = false;

  List<MatchSession> _matches = [];
  MatchSession? _selectedMatch;
  MatchChatThread? _selectedThread;
  List<MatchChatMessage> _messages = [];

  bool _showStatsTooltip = true;
  bool _showDraftTooltip = true;
  String _currentGreeting = 'Hola. Bienvenido a tu Chat Coach. ¿Qué analizamos hoy?';

  @override
  void initState() {
    super.initState();
    timeago.setLocaleMessages('es', timeago.EsMessages());
    _loadInitialData();
    _loadMatches();
  }

  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    final greetings = prefs.getStringList('cc_greetings') ?? [];
    
    String greeting = 'Hola. Bienvenido a tu Chat Coach. ¿Qué analizamos hoy?';
    if (greetings.isNotEmpty) {
      greeting = greetings[Random().nextInt(greetings.length)];
    }
    
    setState(() {
      _showStatsTooltip = prefs.getBool('chat_coach_stats_tooltip') ?? true;
      _showDraftTooltip = prefs.getBool('chat_coach_draft_tooltip') ?? true;
      _currentGreeting = greeting;
    });
  }

  Future<void> _hideTooltip(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, false);
    setState(() {
      if (key == 'chat_coach_stats_tooltip') _showStatsTooltip = false;
      if (key == 'chat_coach_draft_tooltip') _showDraftTooltip = false;
    });
  }

  Future<void> _loadMatches() async {
    setState(() => _isLoading = true);
    try {
      final matches = await ChatCoachService.getMatches();
      setState(() {
        _matches = matches;
        if (_matches.isNotEmpty) {
          _selectedMatch = _matches.first;
          if (_selectedMatch!.threads.isNotEmpty) {
            _selectedThread = _selectedMatch!.threads.first;
          }
        }
      });
      if (_selectedThread != null) {
        await _loadMessages(_selectedThread!.id);
      } else if (_selectedMatch != null) {
        // If match has no threads, create one
        await _createNewThread(_selectedMatch!);
      }
    } catch (e) {
      debugPrint('Error loading matches: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createNewThread(MatchSession match) async {
    try {
      setState(() => _isLoading = true);
      final newThread = await ChatCoachService.createThread(match.id);
      setState(() {
        match.threads.add(newThread);
        _selectedMatch = match;
        _selectedThread = newThread;
        _messages = [];
      });
    } catch (e) {
      debugPrint('Error creating thread: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMessages(String threadId) async {
    setState(() => _isLoading = true);
    try {
      final msgs = await ChatCoachService.getMessages(threadId);
      setState(() {
        _messages = msgs;
      });
      _scrollToBottom();
    } catch (e) {
      debugPrint('Error loading messages: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    if (_selectedThread == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay ningún chat activo para enviar mensajes.')),
      );
      return;
    }

    final text = _messageController.text.trim();
    setState(() {
      _messageController.clear();
      _isSending = true;
      _messages.add(MatchChatMessage(
        id: '',
        threadId: _selectedThread!.id,
        role: 'user',
        content: text,
        createdAt: DateTime.now(),
      ));
    });
    _scrollToBottom();

    try {
      final prefs = await SharedPreferences.getInstance();
      final customPrompt = prefs.getString('chat_coach_custom_prompt') ?? '';
      
      final payload = customPrompt.isNotEmpty
          ? 'Instrucción Oculta del Usuario:\n$customPrompt\n\nMensaje real del usuario:\n$text'
          : text;

      MatchChatMessage aiMsg = await ChatCoachService.sendMessage(_selectedThread!.id, payload);
      
      setState(() {
        _messages.add(aiMsg);
      });
      _scrollToBottom();
      
      // If it was the first message, refresh matches to get the new AI-generated title
      if (_messages.length <= 2) {
         _refreshMatchesSilently();
      }
    } catch (e) {
      debugPrint('Error sending message: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al enviar el mensaje.')),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }
  
  Future<void> _refreshMatchesSilently() async {
    try {
      final matches = await ChatCoachService.getMatches();
      setState(() {
        _matches = matches;
        // Re-assign selected match and thread from updated lists to get new title
        if (_selectedMatch != null) {
          _selectedMatch = _matches.firstWhere((m) => m.id == _selectedMatch!.id, orElse: () => _matches.first);
        }
        if (_selectedThread != null && _selectedMatch != null) {
          _selectedThread = _selectedMatch!.threads.firstWhere((t) => t.id == _selectedThread!.id, orElse: () => _selectedMatch!.threads.first);
        }
      });
    } catch (e) {
      debugPrint('Error refreshing matches silently: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(_selectedThread != null ? _selectedThread!.title : 'Chat Coach', style: const TextStyle(color: Colors.white)),
        backgroundColor: AppTheme.background,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      drawer: _buildDrawer(),
      bottomNavigationBar: widget.bottomNavBar,
      body: _isLoading && _messages.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: _messages.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16.0),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final msg = _messages[index];
                            final isUser = msg.role == 'user';

                            String displayContent = msg.content;
                            if (isUser && displayContent.contains('Mensaje real del usuario:\n')) {
                              displayContent = displayContent.split('Mensaje real del usuario:\n').last;
                            }

                            if (isUser) {
                              return _buildUserBubble(displayContent);
                            } else {
                              return _buildAIBubble(displayContent);
                            }
                          },
                        ),
                ),
                _buildInputArea(),
              ],
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.blueAccent.withOpacity(0.5), width: 3),
                  boxShadow: [
                    BoxShadow(color: Colors.blueAccent.withOpacity(0.4), blurRadius: 30, spreadRadius: 5),
                  ],
                  image: const DecorationImage(
                    image: AssetImage('assets/images/cc_mascot.jpg'), // Mascot image
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _currentGreeting,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.5, height: 1.3),
              ),
              const SizedBox(height: 12),
              Text(
                'Usa el chat de abajo para comenzar tu análisis post-partida.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
              ),
              const SizedBox(height: 40),

              // Buttons removed

            ],
          ),
        ),
      ),
    );
  }

  // _buildQuickActionChip removed


  Widget _buildUserBubble(String content) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16.0, left: 40.0),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2B32B2), Color(0xFF1488CC)], // Premium Blue Gradient
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20.0),
            topRight: Radius.circular(20.0),
            bottomLeft: Radius.circular(20.0),
            bottomRight: Radius.circular(4.0), // Teardrop effect
          ),
          boxShadow: [
            BoxShadow(color: Colors.blueAccent.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Text(
          content,
          style: const TextStyle(color: Colors.white, fontSize: 15.0, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  Widget _buildAIBubble(String content) {
    return Container(
      margin: const EdgeInsets.only(bottom: 32.0, right: 20.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(right: 12.0, top: 2.0),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: [Colors.purpleAccent, Colors.blueAccent]),
              boxShadow: [BoxShadow(color: Colors.purple.withOpacity(0.3), blurRadius: 8)],
            ),
            child: const Icon(Icons.psychology, color: Colors.white, size: 18),
          ),
          Expanded(
            child: MarkdownBody(
              data: content,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(color: Colors.white70, fontSize: 15.0, height: 1.5),
                h1: const TextStyle(color: Colors.white, fontSize: 22.0, fontWeight: FontWeight.bold),
                h2: const TextStyle(color: Colors.white, fontSize: 20.0, fontWeight: FontWeight.bold),
                h3: const TextStyle(color: Colors.white, fontSize: 18.0, fontWeight: FontWeight.bold),
                listBullet: const TextStyle(color: Colors.white70),
                strong: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                code: TextStyle(color: Colors.blueAccent[100], backgroundColor: Colors.transparent),
                codeblockDecoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  border: Border.all(color: Colors.grey[850]!),
                  borderRadius: BorderRadius.circular(12.0),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _messageController,
      builder: (context, value, child) {
        final text = value.text.trim();
        final wordCount = text.isEmpty ? 0 : text.split(RegExp(r'\s+')).length;
        final isOverLimit = wordCount > 200;

        return SafeArea(
          child: Container(
            margin: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 16.0, top: 8.0),
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
            decoration: BoxDecoration(
              color: Colors.grey[900]?.withOpacity(0.8),
              borderRadius: BorderRadius.circular(30.0),
              border: Border.all(color: Colors.grey[800]!),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 120),
                    child: TextField(
                      controller: _messageController,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      decoration: InputDecoration(
                        hintText: 'Escribe tu reflexión...',
                        hintStyle: TextStyle(color: Colors.grey[500]),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 14.0),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                if (wordCount > 0 && isOverLimit)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14.0, right: 8.0),
                    child: Text(
                      '$wordCount/200',
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12.0),
                    ),
                  ),
                _isSending
                    ? const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.0, color: Colors.blueAccent),
                        ),
                      )
                    : Container(
                        margin: const EdgeInsets.all(4.0),
                        decoration: BoxDecoration(
                          color: isOverLimit || text.isEmpty || _selectedThread == null ? Colors.transparent : Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: Icon(
                            Icons.arrow_upward, 
                            color: isOverLimit || text.isEmpty || _selectedThread == null ? Colors.grey : Colors.black,
                            size: 20,
                          ),
                          onPressed: isOverLimit || text.isEmpty || _selectedThread == null ? null : _sendMessage,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: Colors.grey[900],
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.black),
            child: Text(
              'Menú Chat Coach',
              style: TextStyle(color: Colors.white, fontSize: 24),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.settings, color: Colors.white),
            title: const Text('Configurar Prompts', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context); // Close drawer
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ChatCoachPromptsScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.chat_bubble_outline, color: Colors.white),
            title: const Text('Nueva Conversación', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context); // Close drawer
              if (_matches.isNotEmpty) {
                 _createNewThread(_matches.first);
              } else {
                 ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay partidas disponibles para analizar.')));
              }
            },
          ),
          const Divider(color: Colors.grey),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text('Historial de Partidas', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          ..._matches.map((match) {
            final timeAgoStr = timeago.format(match.createdAt, locale: 'es');

            return ExpansionTile(
              leading: const Icon(Icons.videogame_asset, color: Colors.white),
              title: Text('Partida - $timeAgoStr', style: const TextStyle(color: Colors.white)),
              iconColor: Colors.white,
              collapsedIconColor: Colors.grey,
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: match.screenshots.take(5).map((shot) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4.0),
                          child: CachedNetworkImage(
                            imageUrl: shot.imageUrl,
                            width: 30,
                            height: 30,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              width: 30,
                              height: 30,
                              color: Colors.grey[800],
                            ),
                            errorWidget: (context, url, error) => Container(
                              width: 30,
                              height: 30,
                              color: Colors.grey[800],
                              child: const Icon(Icons.error, size: 15, color: Colors.red),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              children: [
                ...match.threads.map((thread) {
                  final isSelected = _selectedThread?.id == thread.id;
                  return ListTile(
                    selected: isSelected,
                    selectedTileColor: Colors.grey[800],
                    contentPadding: const EdgeInsets.symmetric(horizontal: 32.0),
                    leading: const Icon(Icons.chat_bubble_outline, color: Colors.grey, size: 20),
                    title: Text(
                      thread.title,
                      style: TextStyle(
                        color: isSelected ? Colors.blueAccent : Colors.grey[300],
                        fontSize: 14,
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.redAccent, size: 18),
                      onPressed: () async {
                        // Confirm deletion
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            backgroundColor: AppTheme.surface,
                            title: const Text('Eliminar Chat', style: TextStyle(color: Colors.white)),
                            content: const Text('¿Estás seguro de que deseas eliminar este chat?', style: TextStyle(color: Colors.white70)),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                              TextButton(
                                onPressed: () => Navigator.pop(c, true), 
                                child: const Text('Eliminar', style: TextStyle(color: Colors.redAccent))
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          try {
                            setState(() => _isLoading = true);
                            await ChatCoachService.deleteThread(thread.id);
                            _loadMatches(); // Reload matches after deletion
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al eliminar chat')));
                          } finally {
                            if (mounted) setState(() => _isLoading = false);
                          }
                        }
                      },
                    ),
                    onTap: () {
                      Navigator.pop(context); // Close drawer
                      setState(() {
                        _selectedMatch = match;
                        _selectedThread = thread;
                      });
                      _loadMessages(thread.id);
                    },
                  );
                }).toList(),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 32.0),
                  leading: const Icon(Icons.add, color: Colors.blueAccent, size: 20),
                  title: const Text(
                    '+ Crear nuevo chat',
                    style: TextStyle(color: Colors.blueAccent, fontSize: 14),
                  ),
                  onTap: () {
                    Navigator.pop(context); // Close drawer
                    _createNewThread(match);
                  },
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 32.0),
                  leading: const Icon(Icons.delete_forever, color: Colors.redAccent, size: 20),
                  title: const Text(
                    'Eliminar Partida Completa',
                    style: TextStyle(color: Colors.redAccent, fontSize: 14),
                  ),
                  onTap: () async {
                    Navigator.pop(context); // Close drawer
                    // Confirm deletion
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        backgroundColor: AppTheme.surface,
                        title: const Text('Eliminar Partida', style: TextStyle(color: Colors.white)),
                        content: const Text('¿Estás seguro de que deseas eliminar TODA esta partida, incluyendo sus capturas de pantalla y todos los chats asociados? Esta acción no se puede deshacer.', style: TextStyle(color: Colors.white70)),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                          TextButton(
                            onPressed: () => Navigator.pop(c, true), 
                            child: const Text('Eliminar', style: TextStyle(color: Colors.redAccent))
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      try {
                        setState(() => _isLoading = true);
                        await ChatCoachService.deleteMatch(match.id);
                        if (_selectedMatch?.id == match.id) {
                          _selectedMatch = null;
                          _selectedThread = null;
                          _messages = [];
                        }
                        _loadMatches(); // Reload matches after deletion
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al eliminar partida')));
                      } finally {
                        if (mounted) setState(() => _isLoading = false);
                      }
                    }
                  },
                ),
              ],
            );
          }).toList(),
        ],
      ),
    );
  }
}
