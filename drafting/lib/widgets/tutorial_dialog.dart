import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/services/language_service.dart';

class TutorialDialog extends StatefulWidget {
  const TutorialDialog({super.key});

  static Future<void> checkAndShow(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeen = prefs.getBool('tutorial_seen_v1') ?? false;
    if (!hasSeen && context.mounted) {
      show(context);
    }
  }

  static Future<void> show(BuildContext context) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => const TutorialDialog(),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tutorial_seen_v1', true);
  }

  @override
  State<TutorialDialog> createState() => _TutorialDialogState();
}

class _TutorialDialogState extends State<TutorialDialog> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  List<Map<String, String>> get _steps {
    final lang = LanguageService.instance;
    return [
      {
        'badge': lang.tr('tut_s1_badge'),
        'title': lang.tr('tut_s1_title'),
        'description': lang.tr('tut_s1_desc'),
        'image': 'assets/images/tutorial_step1.jpg',
      },
      {
        'badge': lang.tr('tut_s2_badge'),
        'title': lang.tr('tut_s2_title'),
        'description': lang.tr('tut_s2_desc'),
        'image': 'assets/images/tutorial_step2.jpg',
      },
      {
        'badge': lang.tr('tut_s3_badge'),
        'title': lang.tr('tut_s3_title'),
        'description': lang.tr('tut_s3_desc'),
        'image': 'assets/images/tutorial_step3.jpg',
      },
    ];
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _steps.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1E293B),
              Color(0xFF0B0E14),
            ],
          ),
          border: Border.all(
            color: const Color(0xFF00E5FF).withValues(alpha: 0.35),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                        ),
                        child: const Icon(Icons.school_rounded, color: Color(0xFF00E5FF), size: 18),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        LanguageService.instance.tr('tut_header'),
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 22),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            const Divider(color: Color(0xFF334155), height: 1),

            // PageView Content
            Flexible(
              child: SizedBox(
                height: 380,
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _steps.length,
                  onPageChanged: (idx) {
                    setState(() {
                      _currentPage = idx;
                    });
                  },
                  itemBuilder: (ctx, index) {
                    final step = _steps[index];
                    return SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Graphic Image
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              height: 190,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                              ),
                              child: Image.asset(
                                step['image']!,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Step Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFC89B3C).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFC89B3C).withValues(alpha: 0.5)),
                            ),
                            child: Text(
                              step['badge']!,
                              style: const TextStyle(
                                color: Color(0xFFC89B3C),
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Title
                          Text(
                            step['title']!,
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),

                          // Description
                          Text(
                            step['description']!,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.8),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),

            const Divider(color: Color(0xFF334155), height: 1),

            // Bottom Navigation Footer
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Dots indicator
                  Row(
                    children: List.generate(_steps.length, (idx) {
                      final isActive = idx == _currentPage;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: isActive ? 22 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: isActive ? const Color(0xFF00E5FF) : Colors.white24,
                        ),
                      );
                    }),
                  ),

                  // Action Buttons
                  Row(
                    children: [
                      if (_currentPage < _steps.length - 1)
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(LanguageService.instance.tr('tut_skip'), style: const TextStyle(color: Colors.white54)),
                        ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF00E5FF), Color(0xFF0052D4)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF00E5FF).withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: _nextPage,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Text(
                            _currentPage == _steps.length - 1
                                ? LanguageService.instance.tr('tut_start')
                                : LanguageService.instance.tr('tut_next'),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
