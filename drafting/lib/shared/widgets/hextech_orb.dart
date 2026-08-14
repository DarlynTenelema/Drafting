import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;

class HextechOrb extends StatefulWidget {
  final bool isActive;
  final VoidCallback onTap;

  const HextechOrb({
    super.key,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<HextechOrb> createState() => _HextechOrbState();
}

class _HextechOrbState extends State<HextechOrb> with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    // Animación de rotación continua
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15), // Rotación suave y lenta
    )..repeat();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Paleta Hextech
    // Azul brillante cuando está activo, azul oscuro/apagado cuando está inactivo
    final Color orbColor = widget.isActive ? const Color(0xFF00E5FF) : const Color(0xFF006064);
    final Color glowColor = widget.isActive ? const Color(0xFF00B0FF) : const Color(0xFF00363A);
    final Color textColor = widget.isActive ? Colors.white : const Color(0xFFA0E0E0);
    
    // Animación de tamaño y brillo
    final double orbSize = widget.isActive ? 220.0 : 180.0;
    final double glowSpread = widget.isActive ? 25.0 : 10.0;
    final double glowBlur = widget.isActive ? 60.0 : 25.0;

    return GestureDetector(
      onTap: widget.onTap,
      // Usamos AnimatedContainer para manejar la expansión/contracción fluidamente
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCirc,
        width: orbSize,
        height: orbSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: glowColor.withValues(alpha: widget.isActive ? 0.9 : 0.5),
              blurRadius: glowBlur,
              spreadRadius: glowSpread,
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // --- 1. FONDO DE LA ESFERA (Volumen 3D) ---
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    orbColor.withValues(alpha: widget.isActive ? 0.8 : 0.6), // Centro iluminado
                    const Color(0xFF001219), // Borde oscuro para dar profundidad 3D
                  ],
                  stops: const [0.2, 1.0],
                  center: Alignment.topLeft, // Luz viene de arriba a la izquierda
                  radius: 0.9,
                ),
              ),
            ),
            
            // --- 2. ANILLO METÁLICO EXTERIOR ---
            AnimatedBuilder(
              animation: _rotationController,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _rotationController.value * 2.0 * math.pi,
                  child: CustomPaint(
                    painter: _HextechRingPainter(isInner: false),
                    size: const Size(double.infinity, double.infinity),
                  ),
                );
              },
            ),

            // --- 3. ANILLO METÁLICO INTERIOR (Gira en sentido contrario) ---
            AnimatedBuilder(
              animation: _rotationController,
              builder: (context, child) {
                return Transform.rotate(
                  angle: -_rotationController.value * 2.0 * math.pi * 1.5,
                  child: Container(
                    margin: const EdgeInsets.all(18), // Más al centro
                    child: CustomPaint(
                      painter: _HextechRingPainter(isInner: true),
                      size: const Size(double.infinity, double.infinity),
                    ),
                  ),
                );
              },
            ),

            // --- 4. TEXTO CON EFECTO NEÓN ---
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 400),
              style: GoogleFonts.inter(
                fontSize: widget.isActive ? 26 : 20,
                fontWeight: FontWeight.w900,
                color: textColor,
                letterSpacing: 2.5,
                shadows: [
                  Shadow(
                    color: orbColor,
                    blurRadius: widget.isActive ? 20 : 5,
                  ),
                  if (widget.isActive)
                    Shadow(
                      color: Colors.white,
                      blurRadius: 5,
                    ),
                ],
              ),
              child: Text(widget.isActive ? 'ACTIVO' : 'ACTIVAR'),
            ),
          ],
        ),
      ),
    );
  }
}

// Pintor personalizado para crear anillos con aspecto mecánico y huecos
class _HextechRingPainter extends CustomPainter {
  final bool isInner;
  
  _HextechRingPainter({this.isInner = false});

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    
    // Gradiente metálico (Oro/Bronce Hextech)
    final Paint ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = isInner ? 2.5 : 8.0
      ..strokeCap = StrokeCap.square
      ..shader = const SweepGradient(
        colors: [
          Color(0xFFC89B3C), // Oro oscuro
          Color(0xFFF0E6D2), // Brillo luz
          Color(0xFF785A28), // Sombra metal
          Color(0xFFC89B3C), // Oro oscuro
        ],
        stops: [0.0, 0.3, 0.7, 1.0],
      ).createShader(rect);

    final double center = size.width / 2;
    final double radius = center - (ringPaint.strokeWidth / 2);

    // Dibujamos arcos (en lugar de círculos completos) para que parezcan engranajes
    if (isInner) {
      canvas.drawArc(Rect.fromCircle(center: Offset(center, center), radius: radius), 0.0, 1.5, false, ringPaint);
      canvas.drawArc(Rect.fromCircle(center: Offset(center, center), radius: radius), 2.0, 2.5, false, ringPaint);
      canvas.drawArc(Rect.fromCircle(center: Offset(center, center), radius: radius), 4.8, 1.2, false, ringPaint);
    } else {
      // Anillo exterior con huecos diferentes
      canvas.drawArc(Rect.fromCircle(center: Offset(center, center), radius: radius), 0.5, 2.0, false, ringPaint);
      canvas.drawArc(Rect.fromCircle(center: Offset(center, center), radius: radius), 2.8, 2.0, false, ringPaint);
      canvas.drawArc(Rect.fromCircle(center: Offset(center, center), radius: radius), 5.2, 1.0, false, ringPaint);
      
      // Puntos de luz (remaches mágicos) en los cortes
      final Paint dotPaint = Paint()
        ..color = const Color(0xFFF0E6D2)
        ..style = PaintingStyle.fill;
        
      canvas.drawCircle(Offset(center + radius * math.cos(0.5), center + radius * math.sin(0.5)), 4, dotPaint);
      canvas.drawCircle(Offset(center + radius * math.cos(2.8), center + radius * math.sin(2.8)), 4, dotPaint);
      canvas.drawCircle(Offset(center + radius * math.cos(5.2), center + radius * math.sin(5.2)), 4, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false; // Los anillos son estáticos en su dibujo, solo rotan externamente
}
