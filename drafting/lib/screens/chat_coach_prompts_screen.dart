import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        const SnackBar(content: Text('Instrucciones guardadas localmente.')),
      );
    }
  }

  void _addPromptField() {
    if (_controllers.length < 5) {
      setState(() {
        _controllers.add(TextEditingController());
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Solo puedes agregar un máximo de 5 instrucciones.')),
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Configurar Prompts', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Instrucciones para tu AI Coach (Max 5)',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Puedes añadir hasta 5 indicaciones de máximo 50 palabras cada una.',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _controllers.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: _buildPromptField(index),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_controllers.length < 5)
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.blueAccent),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.0),
                          ),
                        ),
                        icon: const Icon(Icons.add, color: Colors.blueAccent),
                        label: const Text('Añadir otra instrucción', style: TextStyle(color: Colors.blueAccent, fontSize: 16)),
                        onPressed: _addPromptField,
                      ),
                    ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                      ),
                      onPressed: _savePrompts,
                      child: const Text('Guardar', style: TextStyle(fontSize: 16, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildPromptField(int index) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _controllers[index],
      builder: (context, value, child) {
        final text = value.text.trim();
        final wordCount = text.isEmpty ? 0 : text.split(RegExp(r'\s+')).length;
        final isOverLimit = wordCount > 50;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controllers[index],
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Ej: Enfócate en el macro-juego...',
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: Colors.grey[900],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: BorderSide.none,
                      ),
                      errorText: isOverLimit ? 'Límite de 50 palabras superado' : null,
                    ),
                  ),
                ),
                if (_controllers.length > 1)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    onPressed: () => _removePromptField(index),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4.0, right: 8.0),
              child: Text(
                '$wordCount / 50 palabras',
                style: TextStyle(
                  color: isOverLimit ? Colors.redAccent : Colors.grey,
                  fontSize: 12.0,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
