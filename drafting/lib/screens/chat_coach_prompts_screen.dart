import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

class ChatCoachPromptsScreen extends StatefulWidget {
  const ChatCoachPromptsScreen({super.key});

  @override
  State<ChatCoachPromptsScreen> createState() => _ChatCoachPromptsScreenState();
}

class _ChatCoachPromptsScreenState extends State<ChatCoachPromptsScreen> {
  List<TextEditingController> _controllers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPrompts();
  }

  Future<void> _loadPrompts() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPromptsStr = prefs.getString('chat_coach_custom_prompts');
    
    if (savedPromptsStr != null && savedPromptsStr.isNotEmpty) {
      try {
        final List<dynamic> savedPrompts = jsonDecode(savedPromptsStr);
        for (String prompt in savedPrompts) {
          _controllers.add(TextEditingController(text: prompt));
        }
      } catch (e) {
        // Fallback for old single prompt
        final oldPrompt = prefs.getString('chat_coach_custom_prompt') ?? '';
        if (oldPrompt.isNotEmpty) {
          _controllers.add(TextEditingController(text: oldPrompt));
        }
      }
    }

    if (_controllers.isEmpty) {
      _controllers.add(TextEditingController());
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _savePrompts() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> promptsToSave = [];
    
    for (var ctrl in _controllers) {
      final text = ctrl.text.trim();
      if (text.isNotEmpty) {
        // Enforce 50 words limit just in case
        final words = text.split(RegExp(r'\s+'));
        if (words.length <= 50) {
          promptsToSave.add(text);
        } else {
          promptsToSave.add(words.take(50).join(' '));
        }
      }
    }

    await prefs.setString('chat_coach_custom_prompts', jsonEncode(promptsToSave));
    
    // Also save combined prompt for the chat screen to use easily
    final combinedPrompt = promptsToSave.join('\n\n- ');
    await prefs.setString('chat_coach_custom_prompt', combinedPrompt.isEmpty ? '' : '- $combinedPrompt');
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Instrucciones guardadas exitosamente.'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context); // Go back after saving
    }
  }

  void _addPromptField() {
    if (_controllers.length < 5) {
      setState(() {
        _controllers.add(TextEditingController());
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Solo puedes agregar un máximo de 5 instrucciones.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _removePromptField(int index) {
    setState(() {
      _controllers[index].dispose();
      _controllers.removeAt(index);
    });
  }

  @override
  void dispose() {
    for (var ctrl in _controllers) {
      ctrl.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Configuración IA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Section
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blueAccent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.auto_awesome, color: Colors.blueAccent, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'Entrena a tu Coach',
                                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.5),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Personaliza hasta 5 reglas para el análisis de tus partidas.',
                                style: TextStyle(color: Colors.white60, fontSize: 14, height: 1.4),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    
                    // Prompts List
                    Expanded(
                      child: ListView.separated(
                        itemCount: _controllers.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 16),
                        itemBuilder: (context, index) {
                          return _buildEnhancedPromptField(index);
                        },
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Add Button
                    if (_controllers.length < 5)
                      Container(
                        width: double.infinity,
                        height: 56,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16.0),
                          border: Border.all(color: Colors.blueAccent.withOpacity(0.5), width: 1.5),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16.0),
                            onTap: _addPromptField,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(Icons.add_circle_outline, color: Colors.blueAccent, size: 20),
                                SizedBox(width: 8),
                                Text('Añadir nueva instrucción', style: TextStyle(color: Colors.blueAccent, fontSize: 16, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                      ),

                    // Save Button
                    Container(
                      width: double.infinity,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF2B32B2), Color(0xFF1488CC)], // Premium Blue
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(16.0),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blueAccent.withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
                        ),
                        onPressed: _savePrompts,
                        child: const Text('Guardar Configuración', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildEnhancedPromptField(int index) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _controllers[index],
      builder: (context, value, child) {
        final text = value.text.trim();
        final wordCount = text.isEmpty ? 0 : text.split(RegExp(r'\s+')).length;
        final isOverLimit = wordCount > 50;

        return Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16.0),
            border: Border.all(color: isOverLimit ? Colors.redAccent.withOpacity(0.5) : Colors.white10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(4.0),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0, left: 12.0, right: 4.0),
                    child: Text(
                      '${index + 1}.',
                      style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controllers[index],
                      maxLines: 3,
                      minLines: 2,
                      style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
                      decoration: InputDecoration(
                        hintText: 'Ej: Enfócate en mi toma de decisiones en mid-game...',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 16.0),
                      ),
                    ),
                  ),
                  if (_controllers.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0, right: 4.0),
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white30, size: 20),
                        onPressed: () => _removePromptField(index),
                        splashRadius: 20,
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 16.0, bottom: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '$wordCount / 50',
                      style: TextStyle(
                        color: isOverLimit ? Colors.redAccent : Colors.white54,
                        fontSize: 12.0,
                        fontWeight: isOverLimit ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
