import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:drafting/theme/app_theme.dart';

class Question {
  final String text;
  final List<String> options;
  final int correctOptionIndex;

  Question({
    required this.text,
    required this.options,
    required this.correctOptionIndex,
  });
}

class TriviaScreen extends StatefulWidget {
  final Widget? bottomNavBar;
  const TriviaScreen({super.key, this.bottomNavBar});

  @override
  State<TriviaScreen> createState() => _TriviaScreenState();
}

class _TriviaScreenState extends State<TriviaScreen> {
  final List<Question> _allQuestions = [
    Question(
      text: '¿Cuál es el mejor ítem contra campeones de mucha curación?',
      options: ['Rey Arruinado', 'Malla de Espinas', 'Sombrero de Rabadon', 'Rencor de Serylda'],
      correctOptionIndex: 1,
    ),
    Question(
      text: '¿Qué dragón otorga velocidad de movimiento y reducción de enfriamiento a la definitiva?',
      options: ['Dragón Infernal', 'Dragón de los Océanos', 'Dragón de las Nubes', 'Dragón de la Montaña'],
      correctOptionIndex: 2,
    ),
    Question(
      text: '¿Qué ítem mítico/legendario otorga un escudo al recibir daño mágico letal?',
      options: ['Fauces de Malmortius', 'Ángel Guardián', 'Reloj de Arena de Zhonya', 'Guantelete de Hielo'],
      correctOptionIndex: 0,
    ),
  ];

  late List<Question> _shuffledQuestions;
  int _currentIndex = 0;
  int? _selectedOptionIndex;
  bool _isAnswered = false;

  // Nuevas variables para la lógica de Vidas y Temporizador
  int _lives = 3;
  int _timeLeft = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _initRandomQuestions();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _initRandomQuestions() {
    _shuffledQuestions = List<Question>.from(_allQuestions);
    _shuffledQuestions.shuffle(Random());
  }

  void _startTimer() {
    _timer?.cancel();
    _timeLeft = 30;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_timeLeft > 0) {
          _timeLeft--;
        } else {
          _timer?.cancel();
          _handleTimeOut();
        }
      });
    });
  }

  void _handleTimeOut() {
    // Si se acaba el tiempo, pierde una vida
    _loseLife();
    if (_lives > 0) {
      _nextQuestion();
    }
  }

  void _loseLife() {
    setState(() {
      _lives--;
    });
    if (_lives <= 0) {
      _timer?.cancel();
      _showOutOfLivesDialog();
    }
  }

  void _handleOptionSelected(int index) {
    if (_isAnswered || _lives <= 0) return;

    _timer?.cancel(); // Detener el temporizador al responder

    setState(() {
      _selectedOptionIndex = index;
      _isAnswered = true;
    });

    final isCorrect = _shuffledQuestions[_currentIndex].correctOptionIndex == index;
    if (!isCorrect) {
      _lives--;
    }

    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      if (_lives <= 0) {
        _showOutOfLivesDialog();
      } else {
        _nextQuestion();
      }
    });
  }

  void _nextQuestion() {
    if (_currentIndex < _shuffledQuestions.length - 1) {
      setState(() {
        _currentIndex++;
        _selectedOptionIndex = null;
        _isAnswered = false;
      });
      _startTimer();
    } else {
      _showCompletionDialog();
    }
  }

  void _showOutOfLivesDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('¡Te quedaste sin vidas!', style: TextStyle(color: AppTheme.textLight)),
        content: const Text(
          'Mira un video corto para recuperar tus 3 vidas y seguir jugando.',
          style: TextStyle(color: AppTheme.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Cerrar diálogo
              Navigator.pop(context); // Salir de la pantalla de trivia
            },
            child: const Text('Salir', style: TextStyle(color: Colors.redAccent)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.play_circle_fill),
            label: const Text('Ver Video'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            onPressed: () {
              // TODO: Aquí llamaremos al anuncio de video bonificado (Rewarded Ad)
              // Simulamos que el usuario vio el video con éxito:
              Navigator.pop(context);
              setState(() {
                _lives = 3; // Recargar vidas
                _selectedOptionIndex = null;
                _isAnswered = false;
              });
              _startTimer();
            },
          ),
        ],
      ),
    );
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('¡Completado!', style: TextStyle(color: AppTheme.textLight)),
        content: const Text(
          'Has terminado todas las preguntas.',
          style: TextStyle(color: AppTheme.textMuted),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Salir'),
          ),
        ],
      ),
    );
  }

  // Construye la UI de los corazones
  Widget _buildLivesIndicator() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return Icon(
          index < _lives ? Icons.favorite : Icons.favorite_border,
          color: Colors.redAccent,
          size: 24,
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_shuffledQuestions.isEmpty) return const SizedBox();
    
    final currentQuestion = _shuffledQuestions[_currentIndex];

    return Scaffold(
      backgroundColor: AppTheme.background,
      bottomNavigationBar: widget.bottomNavBar,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textLight),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Trivia', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textLight)),
        actions: [
          _buildLivesIndicator(),
          const SizedBox(width: 16),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Temporizador y Progreso
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Pregunta ${_currentIndex + 1} de ${_shuffledQuestions.length}',
                          style: const TextStyle(
                            color: AppTheme.accent,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Row(
                          children: [
                            const Icon(Icons.timer, color: Colors.orangeAccent, size: 18),
                            const SizedBox(width: 4),
                            Text(
                              '$_timeLeft s',
                              style: TextStyle(
                                color: _timeLeft <= 5 ? Colors.redAccent : Colors.orangeAccent,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Contenedor de la pregunta
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Text(
                        currentQuestion.text,
                        style: const TextStyle(
                          color: AppTheme.textLight,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Opciones de respuesta
                    ...List.generate(currentQuestion.options.length, (index) {
                      final isSelected = _selectedOptionIndex == index;
                      final isCorrect = currentQuestion.correctOptionIndex == index;
                      
                      Color backgroundColor = AppTheme.surface;
                      Color borderColor = Colors.transparent;
                      Color textColor = AppTheme.textLight;

                      if (_isAnswered) {
                        if (isCorrect) {
                          backgroundColor = Colors.green.withValues(alpha: 0.2);
                          borderColor = Colors.green;
                          textColor = Colors.greenAccent;
                        } else if (isSelected) {
                          backgroundColor = Colors.red.withValues(alpha: 0.2);
                          borderColor = Colors.red;
                          textColor = Colors.redAccent;
                        }
                      } else if (isSelected) {
                        backgroundColor = AppTheme.primary.withValues(alpha: 0.2);
                        borderColor = AppTheme.primary;
                      }

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: GestureDetector(
                          onTap: () => _handleOptionSelected(index),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                            decoration: BoxDecoration(
                              color: backgroundColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: borderColor == Colors.transparent 
                                    ? AppTheme.textMuted.withValues(alpha: 0.2) 
                                    : borderColor,
                                width: 2,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _isAnswered && isCorrect ? Colors.green : AppTheme.background,
                                  ),
                                  child: Text(
                                    String.fromCharCode(65 + index),
                                    style: const TextStyle(color: AppTheme.textLight, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    currentQuestion.options[index],
                                    style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w500),
                                  ),
                                ),
                                if (_isAnswered && isCorrect) const Icon(Icons.check_circle, color: Colors.green),
                                if (_isAnswered && isSelected && !isCorrect) const Icon(Icons.cancel, color: Colors.red),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            
            // --- ESPACIO RESERVADO PARA EL BANNER AD ---
            // Le daremos una altura de 60px que es el estándar de AdMob (320x50 o banner adaptativo)
            Container(
              width: double.infinity,
              height: 60,
              color: AppTheme.surface.withValues(alpha: 0.5),
              alignment: Alignment.center,
              child: const Text(
                'Espacio para Banner AdMob',
                style: TextStyle(color: AppTheme.textMuted, fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
